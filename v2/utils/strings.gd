class_name UtilsStrings extends Node

static func clean_for_node_name(s: String) -> String:
    return s.to_snake_case()
