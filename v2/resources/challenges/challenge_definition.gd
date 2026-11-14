@tool
## One challenge in a bike type's list (BikeTypeDefinition.challenges). ChallengeManager feeds it
## StatsManager.stat_recorded samples of `stat`; done once progress reaches target.
## See Progression.md#challenges.
class_name ChallengeDefinition extends Resource

## How a stat's samples become progress.
enum Goal {
	COUNT, ## +1 per sample at or over min_value (e.g. 10x 5s wheelies)
	TOTAL, ## sum of samples (e.g. 60s of airtime)
	BEST, ## largest single sample (e.g. one 10s wheelie)
}

## Localized title; {target} and {min} are filled in.
@export var title_key: String = ""
## A StatsManager.stat_recorded key: a trick name (one hold's seconds), "airtime" (one jump's
## seconds), "distance", "top_speed", "crashes", or a GameModeType.Kind name + "_played" / "_wins".
@export var stat: String = ""
@export var goal: Goal = Goal.COUNT
@export var target: float = 1.0
## COUNT only: the smallest sample that counts.
@export var min_value: float = 0.0
## Only counts in these gamemodes; empty counts anywhere.
@export var modes: Array[GameModeType.Kind] = []
@export var money: int = 250
@export var xp: int = 50
## Unlocked by finishing it (a TextureMod for bike challenges); empty for none (dailies).
@export var reward_mod: BikeMod


## Progress after one sample.
func apply(progress: float, value: float) -> float:
	match goal:
		Goal.COUNT:
			return progress + (1.0 if value >= min_value else 0.0)
		Goal.TOTAL:
			return progress + value
	return maxf(progress, value)


func title() -> String:
	return tr(title_key).format({"target": "%.0f" % target, "min": "%.0f" % min_value})
