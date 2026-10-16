import { parseQuickAdd } from "./quick-add.js";

// The demo's example projects, matching the screenshots.
const PROJECTS = ["Client work", "Home"];
const PRIORITY_NAMES = { 1: "Low", 2: "Medium", 3: "High" };
const DAY_NAMES = { today: "Today", tomorrow: "Tomorrow" };
const THEME_KEY = "daybar-theme";

function setUpDemo() {
  const input = document.getElementById("demo-input");
  const dayPill = document.getElementById("demo-day");
  const status = document.getElementById("demo-status");
  const slots = Object.fromEntries(
    [...document.querySelectorAll("#demo-chips [data-slot]")].map((chip) => [chip.dataset.slot, chip]),
  );
  if (!input || !dayPill || !status) return;

  // A chip that was hidden plays a short entrance; one that only changes text does not.
  function show(slot, text, level) {
    const chip = slots[slot];
    chip.querySelector(".chip-text").textContent = text;
    if (level) chip.querySelector(".bars").dataset.level = String(level);
    if (chip.hidden) {
      chip.hidden = false;
      chip.classList.remove("chip-new");
      void chip.offsetWidth;
      chip.classList.add("chip-new");
    }
  }

  function render() {
    const result = parseQuickAdd(input.value, PROJECTS);
    const day = result?.day ?? "today";
    dayPill.textContent = DAY_NAMES[day];
    dayPill.toggleAttribute("data-parsed", Boolean(result?.day));

    if (result?.priority) show("priority", PRIORITY_NAMES[result.priority], result.priority);
    else slots.priority.hidden = true;
    if (result?.day) show("day", DAY_NAMES[result.day]);
    else slots.day.hidden = true;
    if (result?.project) show("project", result.project);
    else slots.project.hidden = true;
    return result;
  }

  // Only write when the text changes, so screen readers don't repeat it on every keystroke.
  function say(text) {
    if (status.textContent !== text) status.textContent = text;
  }

  function hintFor(result) {
    if (result) return "Press Return to add it.";
    return input.value.trim() ? "Add a few words for the title too." : "";
  }

  input.addEventListener("input", () => say(hintFor(render())));

  input.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" || event.isComposing) return;
    event.preventDefault();
    const result = parseQuickAdd(input.value, PROJECTS);
    if (!result) {
      say(hintFor(result) || "Type a task first, then press Return.");
      return;
    }
    const where = DAY_NAMES[result.day ?? "today"];
    const extras = [result.priority && `${PRIORITY_NAMES[result.priority]} priority`, result.project]
      .filter(Boolean)
      .join(", ");
    say(`Added “${result.title}” to ${where}${extras ? ` (${extras})` : ""}.`);
    input.value = "";
    render();
  });

  say(hintFor(render()));
}

function setUpThemeSwitch() {
  const fieldset = document.getElementById("theme-switch");
  if (!fieldset) return;
  const root = document.documentElement;
  const darkSources = document.querySelectorAll("source[data-scheme='dark']");

  function apply(choice) {
    if (choice === "light" || choice === "dark") root.dataset.theme = choice;
    else delete root.dataset.theme;
    // <picture> only follows the system setting, so a forced theme rewrites the dark source's media.
    const media = choice === "dark" ? "all" : choice === "light" ? "not all" : "(prefers-color-scheme: dark)";
    darkSources.forEach((source) => { source.media = media; });
  }

  let stored = "auto";
  try {
    stored = localStorage.getItem(THEME_KEY) || "auto";
  } catch (error) {
    // Storage can be blocked; the switch still works for this visit.
  }
  const initial = fieldset.querySelector(`input[value="${stored}"]`) ?? fieldset.querySelector("input[value='auto']");
  initial.checked = true;
  apply(initial.value);

  fieldset.addEventListener("change", (event) => {
    const choice = event.target.value;
    apply(choice);
    try {
      if (choice === "auto") localStorage.removeItem(THEME_KEY);
      else localStorage.setItem(THEME_KEY, choice);
    } catch (error) {
      // Not persisted; nothing else to do.
    }
  });
  fieldset.hidden = false;
}

setUpDemo();
setUpThemeSwitch();
