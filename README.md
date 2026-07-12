# 🐈 cat HAS STOPPED WORKING

A silly first-person work-from-home survival game. Grind through an endless
string of work days while preventing your cat from spending its 9 hearts on the
many, many household hazards it is determined to find. Get paid, buy cat stuff,
sleep, repeat.

## Run it

Any static file server works (three.js loads from CDN, so you need internet):

```sh
cd catgame
python3 -m http.server 8000
```

Then open http://localhost:8000 in Chrome/Firefox/Safari, name your kitten, pick a
coat, and click **BRING KITTY HOME**. You start with one kitten — the shop sells more.

## How to play

- **Intro (day 1):** you arrive home with a meowing carrier. Click it to release
  your new kitten(s), read the tutorial, then head to the office and click the
  computer — today's task list is on it.
- **Difficulty:** you start with one kitten. Want more chaos? Adopt more cats from
  the evening shop (up to four) — each new arrival is more feral than the last, and
  hazards pace up with every extra cat.
- **WASD** move, **Shift** sprint, **mouse** look
- **Left click** — pick up items / fix hazards / use distractions / rescue or grab a cat
- **Right click** — drop what you're holding
- **At the computer:** pick a task with the number keys, **Backspace** returns to
  the task list (progress is saved), **X** steps away.
- **P** pauses the game (outside the computer).
- If you're away from the desk too long you go AWAY and the boss calls the desk
  phone — answer it in time or you're fired (the only way to lose).
- The cats share **9 hearts**. When one is hurting itself you'll hear meowing
  (louder = closer) and the HUD tells you which room it's in.
- **Pacing:** day 1 starts gentle; every day after starts meaner, with more hazards
  armed and the whole house in play.

## The day loop

1. **Morning:** you wake up in bed to furious meowing. Go fill the food bowl —
   breakfast keeps the cats content long enough to start working.
2. **Work:** the computer lists 3–4 tasks drawn from five rotating minigames
   (repeats allowed — some days it's just reports all the way down): write the
   report (typing), organize the calendar (matching), clear the inbox (reply vs.
   spam), fill in the spreadsheet (type each entry's cell — column letter, then
   row number), and the boss call (memory — press **A** to ask him to repeat
   himself). Some days Bob begs you to cover one of his tasks too — it pays extra
   and stays available in the evening. Each finished task pays out; finish the day
   with zero hearts lost for a bonus.
3. **Evening:** the computer turns into the CATS-R-US shop — a proper product
   catalog with pictures, three to a row (arrow keys scroll). Items that haven't
   unlocked yet show as OUT OF STOCK with their restock day. Buy new distractions
   (delivered next morning) or adopt a whole new cat (arrives next morning, named
   and coated to order, adoption fee goes up each time).
4. **Sleep:** click your bed. You get a day summary, the cats sleep 16 hours and
   recover hearts, and it all begins again. Forever. (Overnight, the cats also
   unpack everything you stashed — every morning the hazards are back out.)

**The vet:** the cat never dies. If the hearts drop to the last one, you rush to
the vet — kitty comes back fully healed, and the bill is exactly all of your money.
The rest of that work day is a write-off.

**Distraction boredom:** every use of the same toy halves how long it holds a cat
(down to a 5-second floor) — rotate toys, or buy new ones. Boredom resets overnight.

**"...it's too quiet":** from day 2 on, a cat may silently vanish mid-day. Go find
it — it's just asleep somewhere. Probably.

## The house

Main floor: office, kitchen, main bathroom, TV room, dining room, and a central
hallway. Both staircases are in an enclosed stairwell at the north end of the hall.
Upstairs: bedroom,
guest bedroom, bathroom (with a full tub), closet. Basement: laundry room and a den
with a fireplace.

## Hazards (fix them before the cat finds them)

Toggle hazards (click to fix; some re-arm over time): hot stove, open trash, both
toilet lids, full guest bathtub, kitchen & bedroom windows (the cat can actually get
OUT — grab it back through the window), TV cables, blind cord, balloon, lit candle,
loose air-duct vent (needs the **screwdriver** from the basement workbench), hot iron,
open dryer, mousetrap, dangling string lights, fireplace door.

Stashable hazards (pick up, put in any cupboard/drawer/chest/shelf/cabinet — but
only until tomorrow morning): knives,
chocolate, houseplants (×3), lilies, medicine, ribbon toy, plastic bag, hair ties,
sewing kit, mothballs, detergent pods. **Containers have limited space** (the
medicine cabinet fits 1 thing, most others 2, the toy chest 3).

Dynamic hazards: overfeeding (don't fill the bowl when kitty is already full), and
barf — clean it up before the cat eats it again.

## Distractions (buy yourself typing time)

You start with the cat bed (drop a cat directly on it for a long nap), the treat
jar, the cardboard box, and the laser pointer (hold it, left-click the floor).

Everything else comes from the shop: scratching post ($25), catnip mouse ($30),
window perch ($35), cat tower ($40), robotic mouse ($45, day 3), cat TV ($60,
day 4), and the deluxe cat condo ($100, day 5).
