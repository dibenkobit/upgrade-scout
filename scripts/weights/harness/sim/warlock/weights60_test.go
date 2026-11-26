package warlock

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// The three trees as the UI's preset builds of ui/specs/warlock/dps/builds: gear, talents, demon, consumables,
// options and APL of the build file. Each build file holds a copy of its own gear set
// (ui/specs/warlock/dps/gear_sets/<build>.gear.json), which applying the build equips.
func TestWeights60(t *testing.T) {
	const specs = "../../ui/specs/warlock/dps"
	tree := func(name string, build string, label string, note string) weights60.Tree {
		file := "ui/specs/warlock/dps/builds/" + build + ".build.json"
		return weights60.Tree{
			Class: "Warlock", Tree: name, SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage,
			Player: weights60.JSONBuildPlayer(specs + "/builds/" + build + ".build.json"),
			Baseline: weights60.Baseline{
				Gear:        file + ", its copy of ui/specs/warlock/dps/gear_sets/" + build + ".gear.json ('" + label + "')",
				Talents:     file + " ('" + label + "')",
				Rotation:    "the APL of " + file,
				Consumables: file,
				Quality:     "preset",
				Note:        "UI preset build '" + label + "'. " + note,
			},
		}
	}
	weights60.Run(t, "sim/warlock", []weights60.Tree{
		tree("Affliction", "sm_ruin", "SM/Ruin", "The UI also has the Affliction build 'Aff (Wrack)'."),
		tree("Demonology", "demo_fire_brand", "Demo (Fire Brand)", "The spec's default. The UI also has the build 'Demo (Shadow Brand)'."),
		tree("Destruction", "destro", "Destro", ""),
	})
}
