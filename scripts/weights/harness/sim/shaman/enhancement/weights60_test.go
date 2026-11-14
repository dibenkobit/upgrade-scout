package enhancement

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Enhancement as the UI's only build, 'Testing' (ui/specs/shaman/enhancement/builds/testing.build.json): its
// gear, talents, APL, consumables and options.
func TestWeights60(t *testing.T) {
	const build = "ui/specs/shaman/enhancement/builds/testing.build.json"
	weights60.Run(t, "sim/shaman/enhancement", []weights60.Tree{{
		Class: "Shaman", Tree: "Enhancement", SimStatus: "Alpha", Reference: proto.Stat_StatAttackPower,
		Player: weights60.JSONBuildPlayer("../../../" + build),
		Baseline: weights60.Baseline{
			Gear:        build + " (DefaultGear 'Testing')",
			Talents:     build + " (StandardTalents)",
			Rotation:    "the APL of " + build + " (ROTATION_PRESET_DEFAULT 'Default')",
			Consumables: build,
			Quality:     "testing",
			Note:        "The repo's only Enhancement preset is a build named 'Testing', with a gear set marked devOnly: there is no pre-raid or raid set for the tree.",
		},
	}})
}
