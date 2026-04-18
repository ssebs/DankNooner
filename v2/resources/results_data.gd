class_name ResultsData extends RefCounted

var title: String
var columns: Array[String]
var rows: Array[Dictionary]


static func create(p_title: String, p_columns: Array[String], p_rows: Array[Dictionary]) -> ResultsData:
	var data := ResultsData.new()
	data.title = p_title
	data.columns = p_columns
	data.rows = p_rows
	return data


func to_dict() -> Dictionary:
	return {
		"title": title,
		"columns": columns,
		"rows": rows,
	}


static func from_dict(d: Dictionary) -> ResultsData:
	var data := ResultsData.new()
	data.title = d["title"]
	data.columns = Array(d["columns"], TYPE_STRING, "", null)
	data.rows = Array(d["rows"], TYPE_DICTIONARY, "", null)
	return data
