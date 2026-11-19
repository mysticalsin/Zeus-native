# Decision

A missing card id does not approve. The id has to be the card on screen.

The 45 s slow-start is unchanged. The quiet interval stays 0.4 s.

## Residual

A terminal answer does not withdraw the card. That withdraw is spec 003. Ticket: `specs/approval-queue/ticket-terminal-withdraw.md`. Until that ticket lands, an Allow aimed at a card the terminal already answered does not approve a different command, and the card can stay up.
