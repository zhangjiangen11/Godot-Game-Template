@tool
class_name DownloadAndUnzip
extends Node

signal request_completed
signal response_received(response_body)
signal request_failed(error : String)

const TEMPORARY_ZIP_PATH = "res://temp.zip"
const RESULT_CANT_CONNECT = "Failed to connect"
const RESULT_CANT_RESOLVE = "Failed to resolve"
const RESULT_CONNECTION_ERROR = "Connection error"
const RESULT_TIMEOUT = "Connection timeout"
const RESULT_SERVER_ERROR = "Server error"
const REQUEST_FAILED = "Error in the request"
const REQUEST_TIMEOUT = "Request timed out on the client side"
const DOWNLOAD_IN_PROGRESS = "Download already in progress"
const EXTRACT_IN_PROGRESS = "Extract already in progress"
const DELETE_IN_PROGRESS = "Delete already in progress"
const FAILED_TO_SAVE_ZIP_FILE = "Failed to save the zip file"
const FAILED_TO_MAKE_EXTRACT_DIR = "Failed to make extract directory"
const DOWNLOADED_ZIP_FILE_DOESNT_EXIST = "The downloaded ZIP file doesn't exist."

enum Stage{
	NONE,
	DOWNLOAD,
	EXTRACT,
	DELETE,
}

@export var zip_url : String
@export_dir var extract_path : String
## Forces a download and extraction even if the files already exist.
@export var force : bool = false
@export_group("Advanced Settings")
@export var request_timeout : float = 10.0
@export var zip_file_path : String = TEMPORARY_ZIP_PATH
@export var delete_zip_file : bool = true
@export var process_time_ratio : float = 0.75

@onready var _http_request : HTTPRequest = $HTTPRequest
@onready var _timeout_timer : Timer= $TimeoutTimer

var timed_out : bool = false
var stage : Stage = Stage.NONE
var zip_reader : ZIPReader = ZIPReader.new()
var zipped_file_paths : PackedStringArray = []
var extracted_file_paths : Array[String] = []
var downloaded_zip_file : bool = false

func get_http_request():
	return _http_request

func get_zip_url() -> String:
	return zip_url

func _zip_exists() -> bool:
	return FileAccess.file_exists(zip_file_path)

func get_request_method() -> int:
	return HTTPClient.METHOD_GET

func request(body : String = "", request_headers : Array = []):
	if stage == Stage.DOWNLOAD:
		request_failed.emit(DOWNLOAD_IN_PROGRESS)
		push_warning(DOWNLOAD_IN_PROGRESS)
		return
	if _zip_exists() and not force:
		_extract_files.call_deferred()
		return
	var local_http_request : HTTPRequest = get_http_request()
	var url : String = get_zip_url()
	var method : int = get_request_method()
	if request_timeout > 0.0:
		local_http_request.timeout = request_timeout
	var error = local_http_request.request(url, request_headers, method, body)
	if error != OK:
		request_failed.emit(REQUEST_FAILED)
		push_error("An error occurred in the HTTP request. %d" % error)
		return
	if request_timeout > 0.0:
		_timeout_timer.start(request_timeout + 1.0)
	stage = Stage.DOWNLOAD

func _delete_zip_file():
	if not delete_zip_file or not downloaded_zip_file: return
	if stage == Stage.DELETE:
		request_failed.emit(DELETE_IN_PROGRESS)
		push_warning(DELETE_IN_PROGRESS)
		return
	stage = Stage.DELETE
	DirAccess.remove_absolute(zip_file_path)
	downloaded_zip_file = false

func _save_zip_file(body : PackedByteArray):
	var file = FileAccess.open(zip_file_path, FileAccess.WRITE)
	if not file:
		request_failed.emit(FAILED_TO_SAVE_ZIP_FILE)
		push_error(FAILED_TO_SAVE_ZIP_FILE)
		return
	file.store_buffer(body)
	file.close()
	downloaded_zip_file = true

func extract_path_exists() -> bool:
	return DirAccess.dir_exists_absolute(extract_path)

func _make_extract_path():
	var err := DirAccess.make_dir_absolute(extract_path)
	if err != OK:
		request_failed.emit(FAILED_TO_MAKE_EXTRACT_DIR)
		push_error(FAILED_TO_MAKE_EXTRACT_DIR)

func _extract_files():
	if stage == Stage.EXTRACT:
		request_failed.emit(EXTRACT_IN_PROGRESS)
		push_warning(EXTRACT_IN_PROGRESS)
		return
	stage = Stage.EXTRACT
	if not _zip_exists():
		request_failed.emit(DOWNLOADED_ZIP_FILE_DOESNT_EXIST)
		push_error(DOWNLOADED_ZIP_FILE_DOESNT_EXIST)
		return
	if not extract_path_exists(): _make_extract_path()
	var err = zip_reader.open(zip_file_path)
	if err != OK:
		return
	zipped_file_paths = zip_reader.get_files()

func _on_request_completed(result, response_code, headers, body):
	# If already timed out on client-side, then return.
	if timed_out: return
	_timeout_timer.stop()
	if _zip_exists(): _delete_zip_file()
	if result == HTTPRequest.RESULT_SUCCESS:
		if body is PackedByteArray:
			_save_zip_file(body)
			_extract_files.call_deferred()
			emit_signal("response_received", body)
	else:
		var error : String
		match(result):
			HTTPRequest.RESULT_CANT_CONNECT:
				error = RESULT_CANT_CONNECT
			HTTPRequest.RESULT_CANT_RESOLVE:
				error = RESULT_CANT_RESOLVE
			HTTPRequest.RESULT_CONNECTION_ERROR:
				error = RESULT_CONNECTION_ERROR
			HTTPRequest.RESULT_TIMEOUT:
				error = RESULT_TIMEOUT
			_:
				error = RESULT_SERVER_ERROR
		request_failed.emit(error)
		push_error("result %d" % result)

func _on_http_request_request_completed(result, response_code, headers, body):
	_on_request_completed(result, response_code, headers, body)

func _on_timeout_timer_timeout():
	timed_out = true
	request_failed.emit(REQUEST_TIMEOUT)
	push_warning(REQUEST_TIMEOUT)

func get_progress():
	if stage == Stage.DOWNLOAD:
		return get_download_progress()
	elif stage == Stage.EXTRACT:
		return get_extraction_progress()
	return 0.0

func get_extraction_progress() -> float:
	if zipped_file_paths.size() == 0:
		return 0.0
	return float(extracted_file_paths.size()) / float(zipped_file_paths.size())

func get_download_progress() -> float:
	var body_size := _http_request.get_body_size()
	if body_size < 1: return 0.0
	return float($HTTPRequest.get_downloaded_bytes()) / float(body_size)

func _zipped_files_remaining() -> int:
	return zipped_file_paths.size() - extracted_file_paths.size()

func _extract_next_zipped_file():
	var path_index = extracted_file_paths.size()
	var zipped_file_path := zipped_file_paths.get(path_index)
	var extract_path_dir := extract_path
	if not extract_path_dir.ends_with("/"):
		extract_path_dir += "/"
	var full_path := extract_path_dir + zipped_file_path
	if full_path.ends_with("/"):
		if not DirAccess.dir_exists_absolute(full_path):
			DirAccess.make_dir_recursive_absolute(full_path)
	else:
		if not FileAccess.file_exists(full_path) or force:
			var file_access := FileAccess.open(full_path, FileAccess.WRITE)
			var file_contents = zip_reader.read_file(zipped_file_path)
			file_access.store_buffer(file_contents)
			file_access.close()
	extracted_file_paths.append(full_path)

func _finish_extraction():
	zip_reader.close()
	_delete_zip_file()
	stage = Stage.NONE
	request_completed.emit()

func _process(delta):
	if stage == Stage.EXTRACT:
		var frame_start_time : float = Time.get_unix_time_from_system()
		var frame_time : float = 0.0
		while (frame_time < delta * process_time_ratio):
			if _zipped_files_remaining() == 0:
				_finish_extraction()
				break
			_extract_next_zipped_file()
			frame_time = Time.get_unix_time_from_system() - frame_start_time
