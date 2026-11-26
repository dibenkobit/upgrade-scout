package enhancement

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Enhancement as the UI's only build, 'Default' (ui/specs/shaman/enhancement/builds/default.build.json), which
// the spec's defaults are read from: its gear, talents, APL, consumables and options (Windfury Weapon on the
// main hand).
func TestWeights60(t *testing.T) {
	const build = "ui/specs/shaman/enhancement/builds/default.build.json"
	weights60.Run(t, "sim/shaman/enhancement", []weights60.Tree{{
		Class: "Shaman", Tree: "Enhancement", SimStatus: "Alpha", Reference: proto.Stat_StatAttackPower,
		Player: weights60.JSONBuildPlayer("../../../" + build),
		Baseline: weights60.Baseline{
			Gear:        build + " (DefaultGear 'Default')",
			Talents:     build + " (StandardTalents 'Standard')",
			Rotation:    "the APL of " + build + " (ROTATION_PRESET_DEFAULT 'Default')",
			Consumables: build,
			Quality:     "preset",
			Note:        "UI preset build 'Default', the spec's default and its only build: a two-hander with Windfury Weapon.",
		},
	}})
}
