package priest

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Shadow as the UI's defaults and its only build, 'Shadow' (ui/specs/priest/dps/defaults.siml): its gear,
// talents, APL, consumables and options.
func TestWeights60(t *testing.T) {
	const defaults = "ui/specs/priest/dps/defaults.siml"
	weights60.Run(t, "sim/priest", []weights60.Tree{{
		Class: "Priest", Tree: "Shadow", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
		Player: weights60.SimlPlayer("../../"+defaults, ""),
		Baseline: weights60.Baseline{
			Gear:        defaults + " (ShadowGear 'Shadow')",
			Talents:     defaults + " (StandardTalents 'Standard')",
			Rotation:    "the APL of " + defaults + " (ROTATION_PRESET_DEFAULT 'Default')",
			Consumables: defaults,
			Quality:     "preset",
			Note:        "UI preset build 'Shadow', the spec's default and its only build.",
		},
	}})
}
