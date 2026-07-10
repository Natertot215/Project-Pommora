## Design Lessons

Product-design rules earned in brainstorm/review arcs — checked before ratifying any new capability or entity.

#### II. Capabilities Are Host-Agnostic, Not Entity-Exclusive

A capability granted exclusively to one entity kind quietly fuses two jobs onto it. Reserving the block surface to the tag tiers made "organizer" and "dashboard" one entity and capped the surface's reach at three groups — the fusion, not the tiers, was the design flaw. When ratifying a capability, ask whether the *capability* and the *entity role* are separable: if they are, spec the capability host-agnostic and let entities opt in (the BlockHost model). One uniform system first; per-host divergence only when a real fork demands it.
