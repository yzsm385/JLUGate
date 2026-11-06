/* 学号 → 学院/单位 检索（JLU GPA · 保研测算）
 *
 * 数据在 data/student-id-prefixes.js（由 build_student_id_data.py 生成）。
 * 本文件只做查询，不含任何 DOM 逻辑，浏览器和 Node 都能用。
 *
 * 用法：
 *   StudentIDIndex.forStudentID("55230123")   // → [{code:"55", year:"2023", entry:软件学院}]
 *   StudentIDIndex.resolveForGPA("55230123")  // → {status:"ok", entry:…}
 *   StudentIDIndex.search("软件")             // → 软件学院 / 软件学院珠海
 */
(function (root) {
  "use strict";

  var DATA = root.STUDENT_ID_PREFIXES;
  var ENTRIES = (DATA && DATA.entries) || [];
  var BY_ID = new Map();
  ENTRIES.forEach(function (e) { BY_ID.set(e.id, e); });

  /* 代码统一成大写、去掉空格；「1」补成「01」 */
  function normalizeCode(value) {
    var s = String(value == null ? "" : value).normalize("NFKC").trim().toUpperCase().replace(/\s+/g, "");
    if (/^\d$/.test(s)) s = "0" + s;
    return s;
  }

  /* 学号只保留数字和大写字母（去掉空格、连字符、邮箱 @ 后缀） */
  function normalizeID(value) {
    var s = String(value == null ? "" : value).normalize("NFKC").toUpperCase();
    var at = s.indexOf("@");
    if (at >= 0) s = s.slice(0, at);
    return s.replace(/[^0-9A-Z]/g, "");
  }

  /* 长代码优先：JX49 先于 JX，199 先于 19 */
  var CODES = Array.from(new Set(ENTRIES.map(function (e) { return e.code; })))
    .sort(function (a, b) { return b.length - a.length || a.localeCompare(b); });

  function byCode(code) {
    var c = normalizeCode(code);
    return ENTRIES.filter(function (e) { return e.code === c; });
  }

  function byId(id) { return BY_ID.get(id) || null; }

  function search(keyword) {
    var q = String(keyword == null ? "" : keyword).normalize("NFKC").trim().toUpperCase();
    if (!q) return ENTRIES.slice();
    return ENTRIES.filter(function (e) {
      var hay = [e.code, e.name, e.raw].concat(e.aliases || []).join(" ").toUpperCase();
      return hay.indexOf(q) !== -1;
    });
  }

  /* 学号格式（2026-11-05 确认）：代码 + 2 位年份 + 2 位班号 + 2 位序号。
   * 例：21 23 01 23 = 21（计算机）、2023 级、01 班、23 号。
   * 代码在最前面，长度 2–4 位（JX49 / XZ27 / 199…），按最长匹配；
   * 所以「20230123」是 20（通信）+ 2023，不是「年份在前」。
   */
  function parse(studentID) {
    var s = normalizeID(studentID);
    if (!s) return null;
    var code = null;
    for (var i = 0; i < CODES.length; i++) {
      if (s.indexOf(CODES[i]) === 0) { code = CODES[i]; break; }
    }
    var year = null;
    if (code) {
      var rest = s.slice(code.length);
      // 完整学号应为「年份 2 + 班号 2 + 序号 2」；短前缀不硬猜年份
      if (rest.length >= 6 && /^\d{2}/.test(rest)) {
        var yy = Number(rest.slice(0, 2));
        year = (yy >= 50 ? "19" : "20") + rest.slice(0, 2);
      }
    }
    return {
      studentID: s,
      year: year,
      offset: 0,
      code: code,
      codeLength: code ? code.length : 0,
      entries: code ? byCode(code) : []
    };
  }

  function forStudentID(studentID) {
    var p = parse(studentID);
    if (!p || !p.code) return [];
    return p.entries.map(function (entry) {
      return {
        offset: p.offset,
        codeLength: p.codeLength,
        year: p.year,
        code: p.code,
        entry: entry
      };
    });
  }

  /* 同码多院（25/81）不替用户写死：返回候选，让用户选一次，记住。
   * 选过之后把 entry.id 传进来，或先 rememberChoice(code, id)，下次就不再多问。
   */
  function evaluate(entry) {
    if (entry.undergraduate === true) return "ok";
    if (entry.undergraduate === false) return "not-undergraduate";
    return "needs-confirmation";
  }

  function resolveForGPA(studentID, choiceId) {
    var p = parse(studentID);
    if (!p || !p.code) {
      return { status: "not-found", studentID: p ? p.studentID : "", entry: null, entries: [] };
    }
    if (p.entries.length === 1) {
      var only = p.entries[0];
      return {
        status: evaluate(only),
        studentID: p.studentID,
        code: p.code,
        entry: only,
        entries: p.entries
      };
    }
    var chosen = null;
    if (choiceId) {
      for (var i = 0; i < p.entries.length; i++) {
        if (p.entries[i].id === choiceId) { chosen = p.entries[i]; break; }
      }
    }
    if (chosen) {
      return {
        status: evaluate(chosen),
        studentID: p.studentID,
        code: p.code,
        entry: chosen,
        entries: p.entries
      };
    }
    return {
      status: "needs-choice",
      studentID: p.studentID,
      code: p.code,
      entry: null,
      entries: p.entries,
      options: p.entries
    };
  }

  /* 用户选过的代码 → 条目 id，存 localStorage；没有 localStorage 时返回空 */
  var CHOICE_KEY = "jlu-student-id-choice-v1";

  function readChoices() {
    try {
      var raw = root.localStorage && root.localStorage.getItem(CHOICE_KEY);
      return raw ? JSON.parse(raw) : {};
    } catch (e) {
      return {};
    }
  }

  function savedChoice(code) {
    return readChoices()[normalizeCode(code)] || null;
  }

  function rememberChoice(code, entryId) {
    var c = normalizeCode(code);
    var entry = byId(entryId);
    if (!entry || entry.code !== c) return false;
    var all = readChoices();
    all[c] = entry.id;
    try {
      root.localStorage.setItem(CHOICE_KEY, JSON.stringify(all));
    } catch (e) {
      return false;
    }
    return true;
  }

  function forgetChoice(code) {
    var c = normalizeCode(code);
    var all = readChoices();
    delete all[c];
    try {
      root.localStorage.setItem(CHOICE_KEY, JSON.stringify(all));
    } catch (e) {
      return false;
    }
    return true;
  }

  /* 有保存过就直接用，没有则返回 needs-choice 让界面弹选择 */
  function resolveWithSaved(studentID) {
    var p = parse(studentID);
    return resolveForGPA(studentID, p ? savedChoice(p.code) : null);
  }

  function candidates(studentID) {
    return forStudentID(studentID);
  }

  function undergraduates() {
    return ENTRIES.filter(function (e) { return e.undergraduate === true; });
  }
  function nonUndergraduates() {
    return ENTRIES.filter(function (e) { return e.undergraduate === false; });
  }
  function uncertain() {
    return ENTRIES.filter(function (e) { return e.undergraduate === null; });
  }

  var API = {
    data: DATA,
    entries: ENTRIES,
    normalizeCode: normalizeCode,
    normalizeID: normalizeID,
    byCode: byCode,
    byId: byId,
    search: search,
    parse: parse,
    forStudentID: forStudentID,
    candidates: candidates,
    resolveForGPA: resolveForGPA,
    resolveWithSaved: resolveWithSaved,
    savedChoice: savedChoice,
    rememberChoice: rememberChoice,
    forgetChoice: forgetChoice,
    undergraduates: undergraduates,
    nonUndergraduates: nonUndergraduates,
    uncertain: uncertain
  };

  root.StudentIDIndex = API;
  if (typeof module !== "undefined" && module.exports) module.exports = API;
})(typeof window !== "undefined" ? window : globalThis);
