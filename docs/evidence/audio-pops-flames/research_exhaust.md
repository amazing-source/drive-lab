# Research the #63 tuning rests on: Aventador SVJ exhaust pops and flames

Section 2 of the researcher agent's note of 2026-10-29 (web search and fetch only), copied verbatim; its "How to read this" key is kept for the confidence and source labels. The note's other sections (launch control, reverse) belong to other workstreams and are not copied here.

## How to read this

- **Confidence.** *Documented*: a Lamborghini document says it, or two independent sources agree. *Likely*: one credible source, or consistent anecdotes. *Unknown*: not found. Gaps are left as gaps.
- **Source type** is in brackets: [official] Lamborghini, [review] press road test, [forum] owner post, [vendor] aftermarket seller.
- **(excerpt only)** means the page blocked my fetch (403, 402 or a bot paywall), so I worked from the quoted excerpt the search engine returned. That is weaker than a page I read in full; it is marked every time.
- **Model.** Very little is written about the SVJ alone. Where a fact comes from the LP700-4 (2011) or the Aventador S (2017), I say so. All of them use the same 7-speed ISR single-clutch gearbox.
- **Stock or modified.** Press-review cars come from Lamborghini's press fleet, so I treat them as stock. That is my inference; no review states it. Owner videos are not used as evidence of stock behaviour.

---

## 2. Exhaust pops and flames

### Hardware facts first

| Finding | Confidence | Sources |
|---|---|---|
| **The SVJ has two large outlets, mounted high in the centre of the rear**, closer to the engine than on other Aventadors. The Aventador S has three single outlets through the bumper. Place emitters accordingly. | Documented | [official] Lamborghini: "higher exhaust outlets" https://lamborghini.com/en-en/history/aventador-svj ; lambocars: "two massive exhaust pipes are mounted higher up at the rear" https://lambocars.com/aventador-svj/ ; [official] Aventador S PDF: "Three single exhaust outlets exit through the rear bumper" (link in section 1) |
| The exhaust is valved, with the valves run by the engine computer. The opening point depends on drive mode and rpm, and **in Corsa the valves open sooner**. | Documented | [official] LP700-4 release: two mufflers "Regulated by valves controlled via the engine management" (link in section 1); [review] Canadian Auto Review SVJ: "Depending on the driving mode, the flap in the exhaust will open at certain RPMs." / "In Corsa, it opens sooner" https://canadianautoreview.ca/review-2019-lamborghini-aventador-lp770-4-svj ; [review] CarAdvice SVJ: in Corsa "its pipes are straight through" https://www.caradvice.com.au/reviews/lamborghini-aventador-svj-review/ (excerpt only) |

### When pops and flames happen

| Situation | Finding (stock car) | Confidence | Sources |
|---|---|---|---|
| Lift-off at high rpm (overrun) | Pops and bangs on overrun. One road test describes "every off-throttle maneuver" in the SVJ Roadster as a "snap, crackle and pop". Road & Track's explanation for the stock Aventador S: the engine runs rich and does not cut fuel at high rpm with the throttle closed. | Documented | [review] Digital Trends SVJ Roadster https://www.digitaltrends.com/cars/lamborghini-aventador-svj-roadster-2020-revew/ ; [review] Canadian Auto Review: "the artillery salvo of pops and bangs on overrun" (link above); [review] Road & Track via Yahoo: "a factory-fresh, totally stock Lamborghini Aventador S"; "cutting fuel at high revs with a closed throttle is for the weak" https://autos.yahoo.com/stock-lamborghini-aventador-much-flamethrower-161213132.html |
| Downshifts | Downshifts are smoother than upshifts and come with "an artillery barrage of pops and crackles". **Not established:** whether the ISR blips the throttle to match revs. One forum owner claims it does not blip in Corsa. | Documented (pops); unknown (blip) | [review] Top Gear SVJ first drive https://www.topgear.com/car-reviews/lamborghini/lp-770-4-superveloce-jota-2dr-isr/first-drive (excerpt only); [forum] https://www.lamborghini-talk.com/threads/corsa-vs-sport-mode.218052/ (excerpt only, single claim) |
| Upshifts (Corsa "gunshot") | Corsa upshifts are a hard, sudden kick ("shotgun blast", "bolt-action rifle"), sometimes violent enough to unsettle the car. One test says up- and downshifts both bring "pops, crackles and bangs". Another describes each shift as "a distinct pop and ping, followed by a satisfying burble from the exhaust". | Documented | [review] Digital Trends SVJ (link in section 1); Digital Trends SVJ Roadster (link above); Top Gear first drive (excerpt only); Top Gear "Noise of the Year": "up- and downshifts are accompanied by a variety of pops, crackles and bangs" https://www.topgear.com/car-news/best-2018/lamborghini-aventador-svj-tg-mags-noise-year (excerpt only); Canadian Auto Review (link above) |
| Cold start | **Nothing found** for a stock SVJ. One owner reports that the car starts quiet in Strada and stays quiet once warm. | Unknown | [forum] FerrariChat: "In strada after warm up it will remain quiet." https://www.ferrarichat.com/forum/threads/aventador-exhaust-note.550348/ (excerpt only) |

### By drive mode

| Mode | Finding | Confidence | Sources |
|---|---|---|---|
| Strada | Quietest. Valves stay closed longer; the car is quiet even when warm. Automatic shifts are slow and soft (100 to 125 ms on the LP700-4). | Likely | FerrariChat (excerpt only); Canadian Auto Review; GTspirit road test (links above) |
| Sport | Louder than Strada, with pops on overrun and downshifts. Shifts feel "brutal". No source separates Sport from Corsa for pops. | Likely | Motoring Research SVJ Roadster: gearbox "feels brutal in Sport and Corsa (track) modes" https://www.motoringresearch.com/car-reviews/lamborghini-aventador-svj-roadster-2020-review/ ; FerrariChat (excerpt only) |
| Corsa | Loudest. Valves open earliest, the hardest upshift kick, and the flame display reported most here. | Documented (valves, upshift); likely (flames) | Canadian Auto Review; Top Gear (excerpt only); Car South Africa: sound especially good "in corsa mode", with a high-rev wail and a flame display https://www.pressreader.com/south-africa/car-south-africa/20190101/281595241623749 (excerpt only) |

### How often, and flames against pops

- **Pops are routine** in Sport and Corsa: on every lift-off from high rpm and on every downshift (Digital Trends: "every off-throttle maneuver"). No source puts a number on it (per minute, per shift). Confidence: likely (qualitative only).
- **Visible flames: the stock car does produce them.** Road & Track filmed a stock Aventador S and called it "as much a flamethrower as it is a car". Digital Trends calls the stock SVJ Roadster's outlets "fire-belching pipes". Canadian Auto Review says it can "spit fire if you even ask it nicely". Confidence: documented that flames occur.
- **How often flames appear, as opposed to pops:** not measured anywhere. They are filmed mostly at dusk or night and at launch; daylight visibility is not documented. Confidence: unknown.
- **Aftermarket cars are a different animal.** Gintani, AFD, Novitec, Capristo, Kline and similar systems are sold on bigger pops and flames ("F1 sound"). Most owner flame videos are of modified cars, and decat or tuned cars also show flames. None of these are evidence for the stock car. [vendor] e.g. https://www.supercars.net/blog/?p=815558 (Gintani) ; https://www.aeroflowdynamics.com/blogs/news/unleashing-the-f1-sound-transform-your-aventador-with-the-afd-uhp-exhaust-system (vendor claim, excerpt only)

### Implications for a simulation (exhaust)

- Scale pops by drive mode: **Strada** rare or none, **Sport** pops on lift-off and downshift, **Corsa** the most, plus a sharp crack on every upshift under load.
- **Overrun trigger:** throttle closes at high rpm (exact rpm threshold not documented; make it tunable) gives a burst of pops lasting a moment, not a continuous crackle. Fire it on every qualifying lift-off in Sport and Corsa.
- **Downshift:** a burst of pops on each paddle downshift. Do not add a rev-match blip as a documented behaviour; if we add one, label it a design choice.
- **Upshift (Corsa, high load):** one hard "bang" or crack with the 50 ms shift kick. The "gunshot" feel comes from the shift itself plus the exhaust, and reviewers describe both.
- **Flames:** visible flames are a real stock behaviour, but rarer than pops. Use flames on a subset of Corsa or Sport overrun events and on a warm launch, and make them read better in low light. The exact ratio is ours to tune and is not a sourced number.
- **Emitters** at the SVJ's **two high centre outlets**, not three bumper-level ones.
- **Cold start:** nothing sourced. Do not invent a cold-start pop or flame; keep Strada quiet.

---

**Exhaust items from the note's "Not verified" list:** whether downshifts blip the throttle; the rpm at which overrun pops begin; any number for how often pops or flames occur; stock cold-start behaviour; the rpm at which the valves open in each mode.
