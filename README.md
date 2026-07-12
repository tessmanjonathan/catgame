# 🐈 cat HAS STOPPED WORKING

A silly first-person work-from-home survival game. Finish your report before the
deadline while preventing your cat from spending its 9 lives on the many, many
household hazards it is determined to find.

## Run it

Any static file server works (three.js loads from CDN, so you need internet):

```sh
cd catgame
python3 -m http.server 8000
```

Then open http://localhost:8000 in Chrome/Firefox/Safari, name your kitten, pick a
coat and a chaos level, and click **BRING KITTY HOME**.

## How to play

- **Intro:** you arrive home with a meowing carrier. Click it to release your new
  kitten(s), read the tutorial, then head to the office and click the computer —
  the report deadline only starts once you begin working.
- **Difficulty:** Level 1 is one calm kitten. Level 2 adopts a second, more chaotic
  cat. Level 3 is three cats, one of them feral.
- **WASD** move, **Shift** sprint, **mouse** look
- **Left click** — pick up items / fix hazards / use distractions / rescue or grab a cat
- **Right click** — drop what you're holding
- **Click the computer** at your desk to work: the camera zooms to the monitor and
  you type the gibberish words on-screen. **ESC** steps away (click to re-grab the
  mouse; WASD works either way).
- If you're away from the desk too long you go AWAY and the boss calls the desk
  phone — answer it in time or you're fired.
- The cats share **9 hearts**. When one is hurting itself you'll hear meowing
  (louder = closer) and the HUD tells you which room it's in.
- **Pacing:** the first few minutes only easy hazards (ribbon toy, open toilet) are
  live and the cats stay on the main floor. Mid-game more hazards arm and the cats
  take the stairs; late game the whole house is fair game and everything can arm.

## The house

Main floor: office, kitchen, main bathroom, TV room, dining room, and a central
hallway. Both staircases are in an enclosed stairwell at the north end of the hall —
follow the hanging **green UP** / **orange DOWN** arrow signs. Upstairs: bedroom,
guest bedroom, bathroom (with a full tub), closet. Basement: laundry room and a den
with a fireplace.

## Hazards (fix them before the cat finds them)

Toggle hazards (click to fix; some re-arm over time): hot stove, open trash, both
toilet lids, full guest bathtub, kitchen & bedroom windows (the cat can actually get
OUT — grab it back through the window), TV cables, blind cord, balloon, lit candle,
loose air-duct vent (needs the **screwdriver** from the basement workbench), hot iron,
open dryer, mousetrap, dangling string lights, fireplace door.

Stashable hazards (pick up, put in any cupboard/drawer/chest/shelf/cabinet): knives,
chocolate, houseplants (×3), lilies, medicine, ribbon toy, plastic bag, hair ties,
sewing kit, mothballs, detergent pods.

Dynamic hazards: overfeeding (don't fill the bowl when kitty is already full), and
barf — clean it up before the cat eats it again.

## Distractions (buy yourself typing time)

Cat bed (drop the cat directly on it for a long nap), cat tower, cardboard box,
treat jar, food bowl, scratching post, bedroom window perch, catnip mouse in the
basement, and the laser pointer (hold it, left-click the floor).
