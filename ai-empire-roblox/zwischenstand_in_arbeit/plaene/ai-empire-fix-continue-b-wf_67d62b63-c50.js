export const meta = {
  name: 'ai-empire-fix-continue-B',
  description: 'Finish the interrupted fix rounds of the metro, flight and hotelpolish world packages from their reviewer findings',
  phases: [{ title: 'Fix', detail: 'metro + flight + hotelpolish fix rounds (continuation)' }],
}
const ROOT = '/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad'
const prompt = k => `You are the engineer of package "${k}" of the Roblox game "AI Empire". Read your full package brief FIRST: ${ROOT}/agents/${k}/BRIEF_fix.md (it defines your file ownership, the rules, the mandatory verification loop incl. Blender renders, and the final-message format — follow it exactly).
CONTINUATION: you already built this package; an independent reviewer found the issues in ${ROOT}/agents/${k}/REVIEW_last.json. Fix ALL of them (or prove with a test that an issue is wrong), rerun the verification loop, re-render the affected shots and LOOK again. Where a fix needs another package's file, write a precise request to ${ROOT}/design/requests/${k}.md instead.
RESUME: a previous attempt of THIS fix round was interrupted by a usage limit (about 11:50 UTC), and a restart was stopped after ~2 minutes at 15:28 UTC. Your files, your notes in ${ROOT}/agents/${k}/ and the shared task list may already contain part of these fixes: first check each issue's current state (diff against ${ROOT}/agents/stable/snap_1010, your notes, tests, renders), then finish the rest. Other packages run in parallel on their own files — respect the ownership in your brief.
Your package name for GEN/RUNALL_TAG/out/tests/requests: "${k}". Scratch dir: ${ROOT}/agents/${k}/.`
const out = await parallel(['metro', 'flight', 'hotelpolish'].map(k => () => agent(prompt(k), { label: `fix:${k}`, phase: 'Fix' })))
return { metro: out[0], flight: out[1], hotelpolish: out[2] }
