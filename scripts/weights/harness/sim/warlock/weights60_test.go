package warlock

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// The three trees as the UI's preset builds of ui/specs/warlock/dps/builds: talents, demon, consumables, options
// and APL of the build file. The UI ships no gear preset for the class, so each build wears the gear set the Go
// suite of that build wears (runBuildSuite in warlock_test.go).
func TestWeights60(t *testing.T) {
	const specs = "../../ui/specs/warlock/dps"
	tree := func(name string, build string, label string, gear string, note string) weights60.Tree {
		player := weights60.JSONBuildPlayer(specs + "/builds/" + build + ".build.json")
		player.Equipment = weights60.Gear(specs+"/gear_sets", gear).GearSet
		return weights60.Tree{
			Class: "Warlock", Tree: name, SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage, Player: player,
			Baseline: weights60.Baseline{
				Gear:        "ui/specs/warlock/dps/gear_sets/" + gear + ".gear.json",
				Talents:     "ui/specs/warlock/dps/builds/" + build + ".build.json ('" + label + "')",
				Rotation:    "the APL of ui/specs/warlock/dps/builds/" + build + ".build.json",
				Consumables: "ui/specs/warlock/dps/builds/" + build + ".build.json",
				Quality:     "testing",
				Note:        "UI preset build '" + label + "' for talents, demon, consumables and rotation. The UI has no gear preset for warlocks: the gear is one of the two class-wide sets the Go suites use, not a set made for the tree. " + note,
			},
		}
	}
	affliction := tree("Affliction", "sm_ruin", "SM/Ruin", "preraid", "The UI also has the Affliction build 'Aff (Wrack)'.")
	demonology := tree("Demonology", "demo_fire_brand", "Demo (Fire Brand)", "preraid", "The UI also has the build 'Demo (Shadow Brand)'.")
	destruction := tree("Destruction", "destro", "Destro", "raid", "")
	affliction.Baseline.GearSharedWith = []string{"Demonology"}
	demonology.Baseline.GearSharedWith = []string{"Affliction"}

	weights60.Run(t, "sim/warlock", []weights60.Tree{affliction, demonology, destruction})
}
