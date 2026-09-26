class_name ResultsData extends RefCounted

var title: String
var columns: Array[String]
var rows: Array[Dictionary]
## Display header per column (e.g. an icon); defaults to the column names.
var headers: Array[String]


static func create(
	p_title: String, p_columns: Array[String], p_rows: Array[Dictionary], p_headers: Array[String] = []
) -> ResultsData:
	var data := ResultsData.new()
	data.title = p_title
	data.columns = p_columns
	data.rows = p_rows
	data.headers = p_columns if p_headers.is_empty() else p_headers
	return data


func to_dict() -> Dictionary:
	return {
		"title": title,
		"columns": columns,
		"rows": rows,
		"headers": headers,
	}


static func from_dict(d: Dictionary) -> ResultsData:
	var data := ResultsData.new()
	data.title = d["title"]
	data.columns = Array(d["columns"], TYPE_STRING, "", null)
	data.rows = Array(d["rows"], TYPE_DICTIONARY, "", null)
	data.headers = Array(d["headers"], TYPE_STRING, "", null)
	return data
