extends Node

func _ready() -> void:
    if "--server" in OS.get_cmdline_user_args():
        var server_script = load("res://scripts/server/session_server.gd")
        add_child(server_script.new())
    else:
        var client_script = load("res://scripts/client/battlefield.gd")
        add_child(client_script.new())
