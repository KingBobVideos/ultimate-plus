# November 20 build update

Includes the latest Lab gameplay and presentation changes for Super Mario and Waluigi, saved Cappy placements, possession accessory visibility changes, Paper Mario v1.2, and the brushed-metal launcher shortcut icon.

Stacked Echoes and the Super Mario possession plugin are enabled. Temporary diagnostic settings have been restored.

Known investigation: Eden logs invalid low-address memory accesses during loading, including with the possession plugin disabled. Similar writes exist in older logs from before the Smashline 2 migration. The responsible code and practical impact remain unconfirmed; the build is playable in user testing.
