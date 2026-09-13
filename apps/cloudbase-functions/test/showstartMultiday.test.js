import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseShowStartDetail } from "../src/functions/parseShowLink/showstartParser.js";

function shanghaiTimestamp(value) {
  return new Date(`${value}+08:00`).getTime();
}

describe("ShowStart multi-day parser", () => {
  it("uses structured start/end timestamps and merges artists across sessions", () => {
    const draft = parseShowStartDetail({
      activityId: 307892,
      activityName: "测试多日音乐节",
      avatar: "https://example.com/showstart-cover.jpg",
      price: "¥299 - 699",
      showTime: "2026.10.02-2026.10.03",
      showStartTime: shanghaiTimestamp("2026-10-02T14:30:00"),
      showEndTime: shanghaiTimestamp("2026-10-03T22:15:00"),
      site: {
        name: "测试场馆",
        address: "测试地址",
        cityName: "上海市"
      },
      sessionUserInfos: [
        {
          title: "10月02日",
          userInfos: [
            { id: 1, name: "艺人 A", avatar: "https://example.com/a.jpg" },
            { id: 2, name: "艺人 B", avatar: "https://example.com/b.jpg" }
          ]
        },
        {
          title: "10月03日",
          userInfos: [
            { id: 2, name: "艺人 B", avatar: "https://example.com/b.jpg" },
            { id: 3, name: "艺人 C", avatar: "https://example.com/c.jpg" }
          ]
        }
      ]
    });

    assert.equal(draft.date, "2026-10-02");
    assert.equal(draft.startTime, "14:30");
    assert.equal(draft.endDate, "2026-10-03");
    assert.equal(draft.endTime, "22:15");
    assert.equal(draft.artist, "艺人 A, 艺人 B, 艺人 C");
    assert.deepEqual(draft.artistAvatarURLs, [
      "https://example.com/a.jpg",
      "https://example.com/b.jpg",
      "https://example.com/c.jpg"
    ]);
  });

  it("keeps the existing showTime fallback for events without structured timestamps", () => {
    const draft = parseShowStartDetail({
      activityName: "测试单日演出",
      showTime: "2026.07.12 周六 20:00",
      sessionUserInfos: [
        { userInfos: [{ name: "测试艺人", avatar: "https://example.com/artist.jpg" }] }
      ]
    });

    assert.equal(draft.date, "2026-07-12");
    assert.equal(draft.startTime, "20:00");
    assert.equal(draft.endDate, "");
    assert.equal(draft.endTime, "");
    assert.equal(draft.artist, "测试艺人");
  });
});
