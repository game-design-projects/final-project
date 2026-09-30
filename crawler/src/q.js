// Question builders matching the TypeSafe SDK's output, with no dependencies (so this runs in a Worker too).
export const noul = (instructions, criteria) => ({ type: "noul", instructions, ...(criteria ? { criteria } : {}) });
export const choice = (instructions, criteria) => ({ type: "choice", instructions, criteria });
export const score = (instructions, criteria) => ({ type: "score", instructions, criteria });
