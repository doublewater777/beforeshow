/** Server-side recognition prompt (zh-Hans), aligned with TimetableImport.strings
 *  plus END/TBA → null and compact-JSON rules used in the VL bench.
 */
export const RECOGNITION_PROMPT_ZH_HANS = `请识别我上传的音乐节时刻表图片，只输出一个 JSON 对象，不要任何解释、标题或 Markdown 代码块。

格式（字段名保持英文）：
{"version":1,"timeZone":null,"days":[{"date":"2026-10-17","stages":[{"name":"STAGE","performances":[{"artist":"ARTIST","start":"18:00","end":"19:00"}]}]}]}

规则：
1. 提取图片中的每一场演出：日期、舞台、艺人、开始时间、结束时间。
2. 艺人名和舞台名按图片原文照抄，不要翻译、改写或纠正。
3. 先按日期、再按舞台归组，演出按图片中的顺序排列。
4. 时间使用 24 小时制 HH:mm。属于前一天排期的午夜后演出，仍放在前一天，时间照图片写（例如 "00:30"）。
5. 日期写成 YYYY-MM-DD；图片没有年份时写成 MM-DD。
6. 任何无法确定的值写 null，不要猜测。图片写 END / TBA 时 end 用 null。
7. 不要添加图片中不存在的演出。
8. timeZone 只在图片明确标注时填写 IANA 时区（例如 "Asia/Shanghai"），否则写 null。
9. 有多张图片时，合并成一个 JSON 输出。
10. 输出必须是单行紧凑 JSON：不要缩进、不要换行、不要 Markdown 代码块。
11. 舞台名照抄，不要加 Stage 前缀。`;

export function buildUserContent(images, prompt = RECOGNITION_PROMPT_ZH_HANS) {
  return [
    ...images.map((image) => ({
      type: "image_url",
      image_url: {
        url: `data:${image.mimeType};base64,${image.base64}`
      }
    })),
    { type: "text", text: prompt }
  ];
}
