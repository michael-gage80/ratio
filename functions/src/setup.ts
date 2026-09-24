// Runs before any function is defined — index.ts imports it first. Global options only
// apply to functions defined after they're set, so this can't live in index.ts's body:
// its imports (and the functions they define) are loaded before the body runs.

import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

initializeApp();
// London, where the data lives (PRD: "Hosting: London region (europe-west2)").
setGlobalOptions({ region: "europe-west2", maxInstances: 10 });
