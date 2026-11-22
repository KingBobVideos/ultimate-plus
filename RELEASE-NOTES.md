# November 22 build update

Fixed missing effects/sound/expression script slots on Mario's custom possession-capture motion, three Waluigi ball motions, and four Bandana Dee charge/hold/walk motions. Original animation poses and visibility tracks are preserved.

Repeated capture tests, including timer expiry and taunt exits, no longer produced the invalid reads at 0x19/0x1A. Follow-up Waluigi and Dee testing also showed none of those reads. The separate low-address loading errors remain under investigation and were also observed with all added mods removed.

All mod folders and stacked Echoes are enabled. No temporary diagnostic bypasses are included.
