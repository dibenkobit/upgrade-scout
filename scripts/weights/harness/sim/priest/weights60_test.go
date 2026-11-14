package priest

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Shadow as the UI's only Shadow build, 'Shadow Testing' (ui/specs/priest/dps/builds/testing.build.json): its
// gear, talents, APL, consumables and options.
func TestWeights60(t *testing.T) {
	const build = "ui/specs/priest/dps/builds/testing.build.json"
	weights60.Run(t, "sim/priest", []weights60.Tree{{
		Class: "Priest", Tree: "Shadow", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
		Player: weights60.JSONBuildPlayer("../../" + build),
		Baseline: weights60.Baseline{
			Gear:        build + " (ShadowTestingGear 'Shadow Testing')",
			Talents:     build + " (StandardTalents 'Standard')",
			Rotation:    "the APL of " + build + " (ROTATION_PRESET_DEFAULT 'Default')",
			Consumables: build,
			Quality:     "testing",
			Note:        "The repo's only Shadow preset is a build named 'Shadow Testing', with a gear set marked devOnly: there is no pre-raid or raid set for the tree.",
		},
	}})
}
