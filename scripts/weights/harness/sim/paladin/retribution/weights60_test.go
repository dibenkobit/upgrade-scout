package retribution

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Retribution as the UI's default build, 'Unsealed Wrath': defaults.siml, which is builds/unsealed_wrath.siml
// with the spec's options. The build's rotation is the UI's Simple rotation, which only the browser turns into
// APL rows: sent as it is, the sim casts nothing. The rows it expands to are apls/default.apl.siml, whose
// variables and groups already stand as the Simple defaults set them (Retribution Aura, Judgement of the
// Crusader assigned, pull range 25, both seals in use), so that file is the rotation here.
func TestWeights60(t *testing.T) {
	const specs = "../../../ui/specs/paladin/retribution"
	player := weights60.SimlPlayer(specs+"/defaults.siml", "")
	player.Rotation = weights60.APL(specs+"/apls", "default").Rotation

	weights60.Run(t, "sim/paladin/retribution", []weights60.Tree{{
		Class: "Paladin", Tree: "Retribution", SimStatus: "Alpha", Reference: proto.Stat_StatAttackPower, Player: player,
		Baseline: weights60.Baseline{
			Gear:        "ui/specs/paladin/retribution/gear_sets/default.gear.siml (DefaultGearPreset 'Default')",
			Talents:     "ui/specs/paladin/retribution/builds/unsealed_wrath.siml (UnsealedWrathTalents)",
			Rotation:    "ui/specs/paladin/retribution/apls/default.apl.siml (DefaultAplPreset 'Default'), which is the UI's Simple rotation at the build's defaults",
			Consumables: "ui/specs/paladin/retribution/builds/unsealed_wrath.siml",
			Quality:     "preset",
			Note:        "UI preset build 'Unsealed Wrath', the spec's default. The gear preset is marked devOnly in the UI. The UI also has the build 'Holy Shock', a caster hybrid with its own gear.",
		},
	}})
}
