package v0_36

import (
	"testing"

	"github.com/hyperspeednetwork/hsnhub/types"
	v034auth "github.com/hyperspeednetwork/hsnhub/x/auth/legacy/v0_34"

	"github.com/stretchr/testify/require"
)

func TestMigrate(t *testing.T) {
	var genesisState GenesisState
	require.NotPanics(t, func() {
		genesisState = Migrate(v034auth.GenesisState{
			CollectedFees: types.Coins{
				{
					Amount: types.NewInt(10),
					Denom:  "hsn",
				},
			},
			Params: v034auth.Params{}, // forwarded structure: filling and checking will be testing a no-op
		})
	})
	require.Equal(t, genesisState, GenesisState{Params: v034auth.Params{}})
}
