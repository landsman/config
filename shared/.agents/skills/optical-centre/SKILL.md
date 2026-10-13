---
name: optical-centre
description: Load before centring something vertically on a page or in a panel — a login box, an empty state, a splash, a single card, a "nothing here yet" message — or when a centred block "looks too low". Carries where the eye's centre is, the golden-section ratio for it, and the CSS that keeps the top reachable when the content outgrows the window.
trigger-keywords: vertical* cent*, vertikáln*, center vertically, centre vertically, vycentr*, optical cent*, optick*, golden ratio, zlatý řez
---

# The optical centre

**A block centred exactly between top and bottom looks low.** The eye's centre
of a page sits a little above the geometric one. Design and print practice
agree on that; no measured UI study says by how much.

**Put it at the golden section:** 38.2 % of the free space above the block,
61.8 % below. A convention rather than a measurement, but the one practice
reaches for, and it looked right when tried against the exact middle.

Two spacers that grow in that ratio, never `justify-content: center` or
`margin: auto` on both sides of a fixed-height box, which push the top out of
reach when the content is taller than the window. The spacers shrink to
nothing instead:

    .page {
      display: flex;
      flex-direction: column;
      min-height: 100dvh;
    }
    .page::before,
    .page::after {
      content: "";
      flex: 382 1 0;
    }
    .page::after {
      flex-grow: 618;
    }

Flex items with an `order` of their own need the spacers ordered around them
(`::before { order: -2 }`, `::after { order: 1 }`). A column that should still
breathe on a short window keeps padding on `.page`; the spacers take only what
is left.

Horizontal centring stays exact — the eye is not biased left or right.
