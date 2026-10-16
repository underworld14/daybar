// Port of Sources/DayBarCore/QuickAdd/QuickAddParser.swift for the landing page demo.
// Keep the two in step: site/tests/quick_add.test.mjs mirrors QuickAddParserTests.

const TODAY_WORDS = new Set(["today"]);
const TOMORROW_WORDS = new Set(["tomorrow", "tmr", "tmrw", "besok"]);
const PRIORITY_MARKS = new Map([["!", 1], ["!!", 2], ["!!!", 3]]);

const normalize = (name) => name.toLowerCase().replace(/[\s_-]/g, "");

// Exact match first, then a unique prefix. Unknown or ambiguous tags stay in the title.
function matchProject(query, projects) {
  const key = normalize(query);
  if (!key) return null;
  const exact = projects.find((name) => normalize(name) === key);
  if (exact) return exact;
  const prefixed = projects.filter((name) => normalize(name).startsWith(key));
  return prefixed.length === 1 ? prefixed[0] : null;
}

/**
 * "Send invoice !!! besok #client" -> { title: "Send invoice", priority: 3, day: "tomorrow",
 * project: "Client work" }. Returns null when nothing but syntax (or whitespace) was typed.
 * The last token of each kind wins; a leading backslash keeps a word literal.
 */
export function parseQuickAdd(text, projects = []) {
  const words = text.split(/\s+/).filter(Boolean);
  const titleWords = [];
  const tokens = [];
  let priority = null;
  let day = null;
  let project = null;

  for (let index = 0; index < words.length; index += 1) {
    const word = words[index];
    const lower = word.toLowerCase();

    if (word.startsWith("\\") && word.length > 1) {
      titleWords.push(word.slice(1));
    } else if (PRIORITY_MARKS.has(word)) {
      priority = PRIORITY_MARKS.get(word);
      tokens.push({ kind: "priority", value: priority, source: word });
    } else if (lower === "hari" && words[index + 1]?.toLowerCase() === "ini") {
      day = "today";
      tokens.push({ kind: "day", value: day, source: `${word} ${words[index + 1]}` });
      index += 1;
    } else if (TODAY_WORDS.has(lower)) {
      day = "today";
      tokens.push({ kind: "day", value: day, source: word });
    } else if (TOMORROW_WORDS.has(lower)) {
      day = "tomorrow";
      tokens.push({ kind: "day", value: day, source: word });
    } else if (word.startsWith("#") && word.length > 1 && matchProject(word.slice(1), projects)) {
      project = matchProject(word.slice(1), projects);
      tokens.push({ kind: "project", value: project, source: word });
    } else {
      titleWords.push(word);
    }
  }

  const title = titleWords.join(" ");
  if (!title) return null;
  return { title, priority, day, project, tokens };
}
