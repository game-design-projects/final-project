// donjon-asr: hold-to-talk speech recognition for Donjon, on the player's own machine (no server).
// A streaming transducer (NVIDIA Nemotron Speech Streaming, 160 ms chunks, int8) run by sherpa-onnx's C API.
// The game (src/audio/asr.gd) starts it once, waits for "ready", and talks to it over stdin/stdout:
//
//   in:  frames of 1 tag byte, a uint32 little-endian payload length, then the payload
//        'S' start an utterance (with 0.3 s of silence before it); payload: int32 LE sample rate of the audio that
//            follows (sherpa-onnx resamples)
//        'A' audio; payload: float32 LE mono samples in -1..1
//        'F' finish: decode what is left (after half a second of silence) and report the final text
//        'X' abort: drop the utterance without a result
//   out: one JSON object per line
//        {"event":"ready"}                    the model is loaded
//        {"event":"text","text":"..."}        the words so far, each time they change
//        {"event":"final","text":"..."}       after 'F'
//        {"event":"error","message":"..."}    then exit 1 (bad arguments, the model failed to load, a broken frame)
//   Closing stdin ends it (exit 0).
//
// Frames may be sent before "ready": they wait in a queue until the model is loaded.
// One stream per utterance, no endpointing (resetting a stream mid-sentence loses its context), greedy search with
// blank_penalty 1, one thread: the settings that held up in the class-note app this comes from.
//
//   donjon-asr --tokens=tokens.txt --encoder=encoder.int8.onnx --decoder=decoder.int8.onnx --joiner=joiner.int8.onnx
//              [--threads=1] [--provider=cpu] [--blank-penalty=1] [--agc=1] [--debug=0]
//
// Build: see native/asr/build.sh. Test: native/asr/smoke.py.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
typedef CRITICAL_SECTION Mutex;
typedef CONDITION_VARIABLE Cond;
#define mutex_init(m) InitializeCriticalSection(m)
#define mutex_lock(m) EnterCriticalSection(m)
#define mutex_unlock(m) LeaveCriticalSection(m)
#define cond_init(c) InitializeConditionVariable(c)
#define cond_wait(c, m) SleepConditionVariableCS(c, m, INFINITE)
#define cond_signal(c) WakeConditionVariable(c)
#else
#include <pthread.h>
typedef pthread_mutex_t Mutex;
typedef pthread_cond_t Cond;
#define mutex_init(m) pthread_mutex_init(m, NULL)
#define mutex_lock(m) pthread_mutex_lock(m)
#define mutex_unlock(m) pthread_mutex_unlock(m)
#define cond_init(c) pthread_cond_init(c, NULL)
#define cond_wait(c, m) pthread_cond_wait(c, m)
#define cond_signal(c) pthread_cond_signal(c)
#endif

#include "sherpa-onnx/c-api/c-api.h"

#define MAX_PAYLOAD (16u * 1024u * 1024u)
#define TAIL_S 0.5f  // silence fed after the last audio of an utterance (see 'F')
#define LEAD_S 0.3f  // and before the first (see 'S')

// Automatic gain: laptop microphones often come in far below full scale. Quiet speech is raised towards
// AGC_TARGET (peak) by at most AGC_MAX_GAIN; loud speech is never turned down.
#define AGC_TARGET 0.3f
#define AGC_MAX_GAIN 8.0f
#define AGC_RELEASE_S 1.5f

static void emit_json_string(const char *s) {
  putchar('"');
  for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
    switch (*p) {
      case '"': fputs("\\\"", stdout); break;
      case '\\': fputs("\\\\", stdout); break;
      case '\n': fputs("\\n", stdout); break;
      case '\r': fputs("\\r", stdout); break;
      case '\t': fputs("\\t", stdout); break;
      default:
        if (*p < 0x20) printf("\\u%04x", *p);
        else putchar(*p);
    }
  }
  putchar('"');
}

static void emit(const char *event, const char *key, const char *value) {
  printf("{\"event\":\"%s\"", event);
  if (key != NULL) {
    printf(",\"%s\":", key);
    emit_json_string(value);
  }
  fputs("}\n", stdout);
  fflush(stdout);
}

static void fail(const char *message) {
  emit("error", "message", message);
  exit(1);
}

static int read_full(void *buf, size_t n) {
  size_t got = 0;
  while (got < n) {
    size_t r = fread((char *)buf + got, 1, n - got, stdin);
    if (r == 0) return 0;
    got += r;
  }
  return 1;
}

// stdin is drained by its own thread into this queue, so the game's writes never meet a full pipe (a non-blocking
// write there would fail halfway through a frame) while the model loads or decoding falls behind
typedef struct Frame {
  struct Frame *next;
  unsigned char tag;  // 0: stdin closed
  uint32_t len;
  float data[];       // the payload (len bytes)
} Frame;

static struct {
  Mutex mutex;
  Cond ready;
  Frame *head, *tail;
} queue;

static void push(Frame *f) {
  f->next = NULL;
  mutex_lock(&queue.mutex);
  if (queue.tail != NULL) queue.tail->next = f;
  else queue.head = f;
  queue.tail = f;
  cond_signal(&queue.ready);
  mutex_unlock(&queue.mutex);
}

static Frame *pop(void) {
  mutex_lock(&queue.mutex);
  while (queue.head == NULL) cond_wait(&queue.ready, &queue.mutex);
  Frame *f = queue.head;
  queue.head = f->next;
  if (queue.head == NULL) queue.tail = NULL;
  mutex_unlock(&queue.mutex);
  return f;
}

static int queue_empty(void) {
  mutex_lock(&queue.mutex);
  int empty = queue.head == NULL;
  mutex_unlock(&queue.mutex);
  return empty;
}

static uint32_t le32(const unsigned char *b) {
  return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

#ifdef _WIN32
static DWORD WINAPI reader(LPVOID unused) {
#else
static void *reader(void *unused) {
#endif
  (void)unused;
  unsigned char head[5];
  for (;;) {
    Frame *f = NULL;
    if (read_full(head, 5)) {
      uint32_t len = le32(head + 1);
      if (len > MAX_PAYLOAD) fail("frame too large");
      f = (Frame *)malloc(sizeof(Frame) + len + sizeof(float));
      if (f == NULL) fail("out of memory");
      f->tag = head[0];
      f->len = len;
      if (len > 0 && !read_full(f->data, len)) f->tag = 0;
    } else {
      f = (Frame *)calloc(1, sizeof(Frame));
      if (f == NULL) fail("out of memory");
    }
    int done = f->tag == 0;
    push(f);
    if (done) return 0;
  }
}

static const char *arg(int argc, char **argv, const char *name, const char *fallback) {
  size_t n = strlen(name);
  for (int i = 1; i < argc; i++) {
    if (strncmp(argv[i], name, n) == 0 && argv[i][n] == '=') return argv[i] + n + 1;
  }
  return fallback;
}

typedef struct {
  const SherpaOnnxOnlineRecognizer *rec;
  const SherpaOnnxOnlineStream *stream;
  int32_t rate;
  char *last;  // the text last reported
  int32_t unreported;  // samples accepted since the words were last reported
  int agc;
  float env;   // the input's peak envelope
  float gain;
} Asr;

static void report(Asr *a, const char *event, int always) {
  const SherpaOnnxOnlineRecognizerResult *r = SherpaOnnxGetOnlineStreamResult(a->rec, a->stream);
  const char *text = (r != NULL && r->text != NULL) ? r->text : "";
  if (always || a->last == NULL || strcmp(text, a->last) != 0) {
    free(a->last);
    a->last = (char *)malloc(strlen(text) + 1);
    if (a->last != NULL) strcpy(a->last, text);
    emit(event, "text", text);
  }
  if (r != NULL) SherpaOnnxDestroyOnlineRecognizerResult(r);
}

static void decode(Asr *a) {
  while (SherpaOnnxIsOnlineStreamReady(a->rec, a->stream)) SherpaOnnxDecodeOnlineStream(a->rec, a->stream);
}

static void drop(Asr *a) {
  if (a->stream != NULL) SherpaOnnxDestroyOnlineStream(a->stream);
  a->stream = NULL;
  free(a->last);
  a->last = NULL;
}

static void apply_agc(Asr *a, float *x, int32_t n) {
  float release = expf(-1.0f / (AGC_RELEASE_S * (float)a->rate));
  for (int32_t i = 0; i < n; i++) {
    float v = fabsf(x[i]);
    a->env = v > a->env ? v : a->env * release;
    float want = a->env > 1e-6f ? AGC_TARGET / a->env : AGC_MAX_GAIN;
    if (want > AGC_MAX_GAIN) want = AGC_MAX_GAIN;
    if (want < 1.0f) want = 1.0f;
    a->gain += (want - a->gain) * (want < a->gain ? 0.01f : 0.0005f);  // duck fast, rise slowly
    float y = x[i] * a->gain;
    x[i] = y > 1.0f ? 1.0f : (y < -1.0f ? -1.0f : y);
  }
}

int main(int argc, char **argv) {
#ifdef _WIN32
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
#endif
  const char *tokens = arg(argc, argv, "--tokens", NULL);
  const char *encoder = arg(argc, argv, "--encoder", NULL);
  const char *decoder = arg(argc, argv, "--decoder", NULL);
  const char *joiner = arg(argc, argv, "--joiner", NULL);
  if (tokens == NULL || encoder == NULL || decoder == NULL || joiner == NULL) {
    fail("usage: donjon-asr --tokens=... --encoder=... --decoder=... --joiner=... [--threads=1] [--provider=cpu] "
         "[--blank-penalty=1] [--agc=1] [--debug=0]");
  }

  SherpaOnnxOnlineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.transducer.encoder = encoder;
  config.model_config.transducer.decoder = decoder;
  config.model_config.transducer.joiner = joiner;
  config.model_config.tokens = tokens;
  config.model_config.num_threads = atoi(arg(argc, argv, "--threads", "1"));
  config.model_config.provider = arg(argc, argv, "--provider", "cpu");
  config.model_config.debug = atoi(arg(argc, argv, "--debug", "0"));
  config.decoding_method = "greedy_search";
  config.max_active_paths = 4;
  config.enable_endpoint = 0;
  config.blank_penalty = (float)atof(arg(argc, argv, "--blank-penalty", "1"));

  mutex_init(&queue.mutex);
  cond_init(&queue.ready);
#ifdef _WIN32
  if (CreateThread(NULL, 0, reader, NULL, 0, NULL) == NULL) fail("could not start the reader thread");
#else
  pthread_t thread;
  if (pthread_create(&thread, NULL, reader, NULL) != 0) fail("could not start the reader thread");
#endif

  Asr a;
  memset(&a, 0, sizeof(a));
  a.agc = atoi(arg(argc, argv, "--agc", "1"));
  a.rec = SherpaOnnxCreateOnlineRecognizer(&config);
  if (a.rec == NULL) fail("could not load the speech model (check the paths and that the files are complete)");
  emit("ready", NULL, NULL);

  for (;;) {
    Frame *f = pop();
    if (f->tag == 0) {
      free(f);
      break;
    }
    switch (f->tag) {
      case 'S': {
        if (f->len != 4) fail("S frame needs a 4-byte sample rate");
        drop(&a);
        a.rate = (int32_t)le32((const unsigned char *)f->data);
        if (a.rate < 8000 || a.rate > 192000) fail("unsupported sample rate");
        a.stream = SherpaOnnxCreateOnlineStream(a.rec);
        if (a.stream == NULL) fail("could not create a stream");
        a.last = (char *)calloc(1, 1);  // report text only once there are words
        a.unreported = 0;
        // Nor does it catch a first word that starts with the stream: the player is often already talking when
        // listening begins ("Know your place" -> "Your place"), so give it a moment of quiet to start from
        float *lead = (float *)calloc((size_t)(a.rate * LEAD_S), sizeof(float));
        if (lead != NULL) {
          SherpaOnnxOnlineStreamAcceptWaveform(a.stream, a.rate, lead, (int32_t)(a.rate * LEAD_S));
          free(lead);
        }
        a.env = AGC_TARGET / 2.0f;
        a.gain = 1.0f;
        break;
      }
      case 'A': {
        if (a.stream == NULL) break;  // audio after an abort: ignore
        int32_t n = (int32_t)(f->len / sizeof(float));
        if (a.agc) apply_agc(&a, f->data, n);
        SherpaOnnxOnlineStreamAcceptWaveform(a.stream, a.rate, f->data, n);
        decode(&a);
        // When behind, catch up before reporting, but still show progress every half second of speech
        a.unreported += n;
        if (queue_empty() || a.unreported >= a.rate / 2) {
          report(&a, "text", 0);
          a.unreported = 0;
        }
        break;
      }
      case 'F': {
        if (a.stream == NULL) {
          emit("final", "text", "");
          break;
        }
        // The streaming model only commits a word once it has heard a little past it: people let go of the key
        // right after their last word, and without this it came back cut ("Insolent morsel" -> "Insol")
        float *tail = (float *)calloc((size_t)(a.rate * TAIL_S), sizeof(float));
        if (tail != NULL) {
          SherpaOnnxOnlineStreamAcceptWaveform(a.stream, a.rate, tail, (int32_t)(a.rate * TAIL_S));
          free(tail);
        }
        SherpaOnnxOnlineStreamInputFinished(a.stream);
        decode(&a);
        report(&a, "final", 1);
        drop(&a);
        break;
      }
      case 'X':
        drop(&a);
        break;
      default:
        fail("unknown frame");
    }
    free(f);
  }
  drop(&a);
  SherpaOnnxDestroyOnlineRecognizer(a.rec);
  return 0;
}
