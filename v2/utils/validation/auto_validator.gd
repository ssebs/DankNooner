## Auto-validates nodes in the "validate" group
##
## Nodes in the "validate" group will be checked for:
## - @export object properties that are null
## - @onready %UniqueNode references that failed to resolve
## - Buttons without corresponding _on_<name>_pressed() handlers
##
## Usage: Call AutoValidator.validate_tree(get_tree()) from main_game.gd after tree is ready


## Validates all nodes in the "validate" group. Call once after tree is ready.
static func validate_tree(tree: SceneTree) -> void:
    if not OS.is_debug_build():
        return

    for node in tree.get_nodes_in_group(UtilsConstants.GROUPS["Validate"]):
        _validate(node)


static func _validate(node: Node) -> void:
    if not is_instance_valid(node):
        return

    var errors: Array[String] = []

    errors.append_array(_check_exports(node))
    errors.append_array(_check_unique_nodes(node))
    errors.append_array(_check_button_handlers(node))

    for error in errors:
        push_error("%s: %s" % [node.name, error])

    if not errors.is_empty():
        assert(false, "%s failed validation with %d error(s)" % [node.name, errors.size()])


#region Export Validation
## Finds all @export vars of Object type and checks they're not null
static func _check_exports(node: Node) -> Array[String]:
    var errors: Array[String] = []

    for prop in node.get_property_list():
        var is_export = (
            prop.usage & PROPERTY_USAGE_EDITOR and prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE
        )
        if not is_export:
            continue
        # Only check Object types (nodes, resources) - skip primitives
        if prop.type != TYPE_OBJECT:
            continue
        var value = node.get(prop.name)
        if value == null:
            errors.append("Export '%s' is null" % prop.name)

    return errors


#endregion


#region Unique Node Validation
## Finds all @onready vars with % prefix and checks they resolved
static func _check_unique_nodes(node: Node) -> Array[String]:
    var errors: Array[String] = []
    var script: Script = node.get_script()

    if script == null:
        return errors

    var source = script.source_code
    if source == null or source.is_empty():
        return errors

    # Match: @onready var something = %Name or @onready var something: Type = %Name
    var regex = RegEx.new()
    regex.compile("@onready\\s+var\\s+(\\w+)[^=]*=\\s*%")

    for result in regex.search_all(source):
        # Skip if this match is on a commented line
        if _is_in_comment(source, result.get_start()):
            continue
        var var_name = result.get_string(1)
        var value = node.get(var_name)
        if value == null:
            errors.append("Unique node '%s' not found" % var_name)

    return errors


## Checks if a position in source code is within a comment
static func _is_in_comment(source: String, pos: int) -> bool:
    # Find the start of the line containing this position
    var line_start = source.rfind("\n", pos)
    if line_start == -1:
        line_start = 0
    else:
        line_start += 1  # Move past the newline

    # Get the text between line start and the match position
    var line_before_match = source.substr(line_start, pos - line_start)

    # Check if there's a # before the match on this line
    return line_before_match.contains("#")


#endregion


#region Button Handler Validation
## Finds @onready Button vars and checks for _on_<name>_pressed method
static func _check_button_handlers(node: Node) -> Array[String]:
    var errors: Array[String] = []
    var script: Script = node.get_script()

    if script == null:
        return errors

    var source = script.source_code
    if source == null or source.is_empty():
        return errors

    # Match: @onready var something: Button = %Name
    var regex = RegEx.new()
    regex.compile("@onready\\s+var\\s+(\\w+)\\s*:\\s*Button")

    for result in regex.search_all(source):
        if _is_in_comment(source, result.get_start()):
            continue
        var var_name = result.get_string(1)
        var handler = _find_button_handler(node, var_name)
        if handler.is_empty():
            var expected = "_on_%s_pressed" % var_name
            errors.append("Button '%s' missing handler (expected '%s')" % [var_name, expected])

    return errors


## Checks multiple naming conventions for button handlers
static func _find_button_handler(node: Node, var_name: String) -> String:
    var candidates: Array[String] = []

    # _on_back_btn_pressed (exact match on var name)
    candidates.append("_on_%s_pressed" % var_name)
    # _on_back_pressed (without _btn suffix)
    var stripped = var_name.replace("_btn", "").replace("_button", "")
    candidates.append("_on_%s_pressed" % stripped)

    for candidate in candidates:
        if node.has_method(candidate):
            return candidate

    return ""

#endregion
