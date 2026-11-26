package elemental

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Elemental as the UI's only build, 'Default' (ui/specs/shaman/elemental/builds/default.build.json), which the
// spec's defaults are read from: its gear, talents, APL, consumables and options.
func TestWeights60(t *testing.T) {
	const build = "ui/specs/shaman/elemental/builds/default.build.json"
	weights60.Run(t, "sim/shaman/elemental", []weights60.Tree{{
		Class: "Shaman", Tree: "Elemental", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
		Player: weights60.JSONBuildPlayer("../../../" + build),
		Baseline: weights60.Baseline{
			Gear:        build + " (DefaultGear 'Default')",
			Talents:     build + " (StandardTalents 'Standard')",
			Rotation:    "the APL of " + build + " (ROTATION_PRESET_DEFAULT 'Default')",
			Consumables: build,
			Quality:     "preset",
			Note:        "UI preset build 'Default', the spec's default and its only build. The UI also has a 'Budget' gear set.",
		},
	}})
}
