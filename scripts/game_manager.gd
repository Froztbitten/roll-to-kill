extends Node

enum Turn { PLAYER, ENEMY }

var current_turn = Turn.PLAYER
var player
var enemy

func next_turn():
	if current_turn == Turn.PLAYER:
		current_turn = Turn.ENEMY
	else:
		current_turn = Turn.PLAYER
