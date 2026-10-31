# Playbooks

A playbook is what an agent reads first, before starting a kind of work again. It gives the order of
work, the checks that catch the expensive mistakes, what each stage really took, and the traps, all
with sources.

The step-by-step how-to lives in [`docs/pipelines/`](../pipelines/README.md). The playbooks link to it
rather than repeat it.

| Playbook | For | Owner |
|---|---|---|
| [NEW_CAR.md](NEW_CAR.md) | The end-to-end runbook for a new car, linking to the two below | game-kit archivist |
| [MODELLING.md](MODELLING.md) | The car's model and interior, from references to the import checks | 3D artist |
| [ANIMATION.md](ANIMATION.md) | The driver's animations and their runtime | animator |

Each playbook comes in its own pull request; a link to one not yet merged resolves once it lands.
