class_name LaunchPlan
extends RefCounted

## The concrete "what would be executed" for one Play press: the VPX
## executable plus the fully expanded argument list. Built from the
## config's launch-args TEMPLATE (design section 6: never a hard-coded
## command line). Pure data + pure functions - the process spawn lives
## in LaunchService, so this is fully testable UI-free.
##
## Template rules: whitespace separates arguments; double quotes group
## (a quoted segment stays ONE argument even with spaces inside); the
## token {table} is replaced by the build's full file path wherever it
## appears. OS.create_process takes an argument array (no shell), so a
## path with spaces inside one array element is already "quoted"
## correctly - the tokenizer's job is keeping it in one element.

var exe_path: String = ""
var args: Array[String] = []
var table_path: String = ""
var game_id: String = ""
var game_title: String = ""
var build_version: String = ""
var valid: bool = false
var error: String = ""


static func build_plan(config: PvldsConfig, game: GameEntry, build: TableBuild) -> LaunchPlan:
	var plan: LaunchPlan = LaunchPlan.new()
	if config == null:
		plan.error = "No config."
		return plan
	if game == null or build == null:
		plan.error = "No table selected."
		return plan
	plan.exe_path = config.vpx_exe_path.strip_edges()
	plan.table_path = build.file_path
	plan.game_id = game.game_id
	plan.game_title = game.title
	plan.build_version = build.version
	if plan.exe_path == "":
		plan.error = "No VPX executable configured."
		return plan
	if plan.table_path == "":
		plan.error = "The selected build has no file path."
		return plan
	var template: String = config.launch_args_template.strip_edges()
	if template == "":
		template = PvldsConfig.DEFAULT_LAUNCH_ARGS
	plan.args = expand_template(template, plan.table_path)
	plan.valid = true
	return plan


## Splits a template into arguments (quote-aware) and substitutes
## {table} in every argument. An unterminated quote groups to the end
## of the template rather than failing - the desk pass shows the
## template to the user, and a forgiving parse beats a dead launcher.
static func expand_template(template: String, table_path: String) -> Array[String]:
	var out: Array[String] = []
	var current: String = ""
	var in_quotes: bool = false
	var has_current: bool = false
	for i: int in range(template.length()):
		var ch: String = template[i]
		if ch == "\"":
			in_quotes = not in_quotes
			has_current = true
		elif not in_quotes and (ch == " " or ch == "\t"):
			if has_current:
				out.append(current.replace("{table}", table_path))
				current = ""
				has_current = false
		else:
			current += ch
			has_current = true
	if has_current:
		out.append(current.replace("{table}", table_path))
	return out
