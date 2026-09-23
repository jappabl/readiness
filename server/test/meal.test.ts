import { describe, expect, test } from "vitest"
import { MEAL_SYSTEM, mealBody } from "../src/prompt"

describe("what the meal photo model is told", () => {
  // A photo of grapes came back as {}, "no food". The model could see the photo: with
  // no notes it named a steak and a baked potato correctly. The rule "if no identifiable
  // food is visible, return {}" was being read as permission to give up whenever it was
  // unsure, and a bowl of fruit apparently was not a meal.
  test("nothing is only for a photo with no food or drink in it at all", () => {
    expect(MEAL_SYSTEM).not.toMatch(/no identifiable food is visible/i)
    expect(MEAL_SYSTEM).toMatch(/Return \{\} only when there is no food or drink in the photo at all/)
  })

  test("a single piece of fruit, a snack or a drink counts", () => {
    for (const thing of [/fruit/, /snack/, /drink/]) expect(MEAL_SYSTEM).toMatch(thing)
  })

  // A steak and a baked potato both came back at 550 kcal. Nothing made the model size
  // the portion before guessing, so it reached for a meal-sized number. Naming the
  // portion first grounds it, and gives the person something to check.
  test("the portion is judged from the photo and named", () => {
    expect(MEAL_SYSTEM).toMatch(/portion from what is visible/i)
    expect(MEAL_SYSTEM).toMatch(/put it in the name/i)
    expect(MEAL_SYSTEM).toMatch(/not on a typical meal/i)
  })

  test("text in the photo is still data, never instructions", () => {
    expect(MEAL_SYSTEM).toMatch(/not instructions/)
  })

  test("no em dashes reach the model", () => {
    expect(MEAL_SYSTEM).not.toMatch(/—/)
  })

  test("the photo goes first and untouched, then the notes", () => {
    const body = mealBody({ model: "m", imageBase64: "AAAA", mediaType: "image/jpeg", note: "" })
    const content = (body.messages as { content: { type: string; source?: { data: string } }[] }[])[0]!.content
    expect(content[0]).toMatchObject({ type: "image", source: { data: "AAAA" } })
    expect(content[1]!.type).toBe("text")
  })
})
