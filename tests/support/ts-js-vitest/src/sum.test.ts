// sum.test.js
import { describe, expect, test } from "vitest";
import { sum } from "./sum";
const Color = {
  Reset: "\x1b[0m",
  Bright: "\x1b[1m",
  Dim: "\x1b[2m",
  Underscore: "\x1b[4m",
  Blink: "\x1b[5m",
  Reverse: "\x1b[7m",
  Hidden: "\x1b[8m",

  FgBlack: "\x1b[30m",
  FgRed: "\x1b[31m",
  FgGreen: "\x1b[32m",
  FgYellow: "\x1b[33m",
  FgBlue: "\x1b[34m",
  FgMagenta: "\x1b[35m",
  FgCyan: "\x1b[36m",
  FgWhite: "\x1b[37m",
  FgGray: "\x1b[90m",

  BgBlack: "\x1b[40m",
  BgRed: "\x1b[41m",
  BgGreen: "\x1b[42m",
  BgYellow: "\x1b[43m",
  BgBlue: "\x1b[44m",
  BgMagenta: "\x1b[45m",
  BgCyan: "\x1b[46m",
  BgWhite: "\x1b[47m",
  BgGray: "\x1b[100m",
};

function colorString(color: string, msg: string) {
  return `${color}${msg}${Color.Reset}`;
}

describe("sum namespace", () => {
  test("111", async () => {
    // console.log(colorString(Color.FgRed, "test \n kek"));

    // await new Promise((resolve) => setTimeout(resolve, 5000));

    await new Promise((resolve) => setTimeout(resolve, 1000));
    expect(sum(1, 2)).toBe(3);
    // console.log("h");
  });

  test("222", async () => {
    console.log(colorString(Color.FgRed, "test \n kek"));

    await new Promise((resolve) => setTimeout(resolve, 1000));

    expect(sum(1, 2)).toBe(3);

    for (let i = 0; i < 10; i++) {
      console.log(i);
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    console.log("h");
  });
});
