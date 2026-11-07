/* JLU GPA · 保研测算 — 交互逻辑 */
(function () {
  "use strict";

  const DATA = window.GPA_DATA;
  if (!DATA) return;

  const META = DATA.meta;
  const BASE_COURSES = DATA.courses.map(function (c, i) {
    return Object.assign({}, c, { _key: "b" + i });
  });
  let COURSES = BASE_COURSES.slice();
  let TOTAL = 0;
  const CUTOFF = META.reference[0].minGpa; // 2026 实际最低线 3.458970
  const COHORT_LABEL = { "2022": "2022级", "2024": "2023/24级", "2025": "2025级", "2026": "2026级" };
  function cohortLabel() { return COHORT_LABEL[state.cohort] || "2022级"; }
  const OFFICIAL = META.officialNote || "2022级官方科目表";

  function isCounted(c) {
    if (state.overrides && Object.prototype.hasOwnProperty.call(state.overrides, c._key)) {
      return !!state.overrides[c._key];
    }
    return !!c.count;
  }
  function countedNow() {
    return COURSES.filter(isCounted).length;
  }
  function recalcTotal() {
    TOTAL = COURSES.reduce(function (s, c) { return s + (isCounted(c) ? c.credit : 0); }, 0);
  }
  function rebuildCourses() {
    const base = state.cohort === "2026" ? [] : BASE_COURSES;
    COURSES = base.concat(state.custom.map(function (c) {
      return Object.assign({}, c, { _key: c.key, custom: true, count: true });
    }));
    recalcTotal();
  }
  const SEM_LABEL = { 1: "大一上", 2: "大一下", 3: "大二上", 4: "大二下", 5: "大三上", 6: "大三下", 7: "大四上", 8: "大四下" };
  const GPA_VALUES = [4.0, 3.7, 3.3, 3.0, 2.7, 2.3, 2.0, 1.7, 1.3, 1.0, 0];
  const SCORE_RANGE = {
    4.0: "90–100", 3.7: "87–89.9", 3.3: "84–86.9", 3.0: "80–83.9",
    2.7: "77–79.9", 2.3: "74–76.9", 2.0: "70–73.9", 1.7: "67–69.9",
    1.3: "64–66.9", 1.0: "60–63.9", 0: "<60"
  };
  const STORE = META.storeKey || "jlu-gpa-sw-2022-v1";
  let FAIL_COUNT = 0;

  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.prototype.slice.call((root || document).querySelectorAll(sel));

  /* ---------------- state ---------------- */
  let state = {
    mode: "gpa",
    target: META.defaultTarget || 3.46,
    cohort: "2022",
    engA: false,
    showAll: false,
    custom: [],
    overrides: {},
    entries: {}
  };

  function load() {
    try {
      const raw = localStorage.getItem(STORE);
      if (!raw) return;
      const s = JSON.parse(raw);
      if (!s || typeof s !== "object") return;
      if (s.mode === "gpa" || s.mode === "score") state.mode = s.mode;
      if (typeof s.target === "number" && s.target >= 0 && s.target <= 4) state.target = s.target;
      state.showAll = !!s.showAll;
      if (s.cohort && COHORT_LABEL[s.cohort]) state.cohort = s.cohort;
      state.engA = !!s.engA;
      if (Array.isArray(s.custom)) {
        state.custom = s.custom.filter(function (c) {
          return c && typeof c.key === "string" && typeof c.name === "string" &&
            isFinite(Number(c.credit)) && Number(c.credit) > 0 && Number(c.sem) >= 1 && Number(c.sem) <= 8;
        }).map(function (c) {
          return { key: c.key, name: String(c.name), credit: Number(c.credit), sem: Number(c.sem), type: c.type || "必修" };
        });
      }
      if (s.overrides && typeof s.overrides === "object") {
        Object.keys(s.overrides).forEach(function (k) {
          if (typeof s.overrides[k] === "boolean") state.overrides[k] = s.overrides[k];
        });
      }
      if (s.entries && typeof s.entries === "object") {
        Object.keys(s.entries).forEach(function (k) {
          const e = s.entries[k];
          const key = /^\d+$/.test(k) ? "b" + k : k;
          if (!e) return;
          const g = Number(e.gpa);
          const sc = e.score == null ? null : Number(e.score);
          if (!isFinite(g) || g < 0 || g > 4) return;
          if (GPA_VALUES.indexOf(g) === -1) return;
          state.entries[key] = { gpa: g, score: isFinite(sc) ? sc : null };
        });
      }
    } catch (err) { /* ignore */ }
  }

  let saveTimer = null;
  function save() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function () {
      try { localStorage.setItem(STORE, JSON.stringify(state)); } catch (err) { /* ignore */ }
    }, 250);
  }

  /* ---------------- helpers ---------------- */
  function bandOf(s) {
    if (!isFinite(s) || s < 0 || s > 100) return null;
    if (s < 60) return { gpa: 0, next: 60 };
    if (s < 64) return { gpa: 1.0, next: 64 };
    if (s < 67) return { gpa: 1.3, next: 67 };
    if (s < 70) return { gpa: 1.7, next: 70 };
    if (s < 74) return { gpa: 2.0, next: 74 };
    if (s < 77) return { gpa: 2.3, next: 77 };
    if (s < 80) return { gpa: 2.7, next: 80 };
    if (s < 84) return { gpa: 3.0, next: 84 };
    if (s < 87) return { gpa: 3.3, next: 87 };
    if (s < 90) return { gpa: 3.7, next: 90 };
    return { gpa: 4.0, next: null };
  }

  function scoreToGpa(s) {
    const b = bandOf(s);
    return b ? b.gpa : null;
  }

  // 距上一档不足 1 分 → 卡绩；返回 {gap, next, up}
  function kaInfo(e) {
    if (!e || e.score == null || e.score < 80) return null;
    const b = bandOf(e.score);
    if (!b || b.next == null) return null;
    const gap = b.next - e.score;
    if (gap > 1 + 1e-9) return null;
    return { gap: gap, next: b.next, up: bandOf(b.next).gpa };
  }

  function gpaToScoreMid(g) {
    const map = { 0: 55, 1.0: 61.5, 1.3: 65, 1.7: 68, 2.0: 71.5, 2.3: 75, 2.7: 78, 3.0: 81.5, 3.3: 85, 3.7: 88, 4.0: 92.5 };
    return map[g] != null ? map[g] : "";
  }

  const fmt = (x, d) => (x == null || !isFinite(x) ? "—" : x.toFixed(d == null ? 1 : d));
  function crText(x) {
    if (Math.abs(x - Math.round(x)) < 1e-9) return String(Math.round(x));
    return x < 1 ? x.toFixed(2) : x.toFixed(1);
  }
  const pct = x => (x * 100).toFixed(1) + "%";

  function entryOf(key) {
    const e = state.entries[key];
    if (!e || e.gpa == null || !isFinite(e.gpa)) return null;
    return e;
  }

  function compute() {
    let eCr = 0, eW = 0, eN = 0, aCr = 0, aW = 0, aN = 0;
    COURSES.forEach(function (c) {
      if (!entryOf(c._key)) return;
      const g = state.entries[c._key].gpa;
      aCr += c.credit; aW += c.credit * g; aN++;
      if (isCounted(c)) { eCr += c.credit; eW += c.credit * g; eN++; }
    });
    return {
      eCr: eCr, eW: eW, eN: eN,
      aCr: aCr, aW: aW, aN: aN,
      gpa: eCr > 0 ? eW / eCr : null,
      allGpa: aCr > 0 ? aW / aCr : null,
      remaining: Math.max(0, TOTAL - eCr),
      remainingN: countedNow() - eN
    };
  }

  function estimateRank(g) {
    if (g == null || !META.distribution) return null;
    const d = META.distribution;
    if (g >= d[0][1]) return 1;
    for (let i = 1; i < d.length; i++) {
      const p = d[i - 1], q = d[i];
      if (g >= q[1]) {
        const t = (p[1] - g) / Math.max(1e-9, p[1] - q[1]);
        return Math.round(p[0] + t * (q[0] - p[0]));
      }
    }
    return d[d.length - 1][0];
  }

  /* ---------------- build tables ---------------- */
  const openState = {};

  function controlHTML(c) {
    const key = c._key;
    const e = state.entries[key];
    if (state.mode === "score") {
      const v = e && e.score != null ? e.score : "";
      const ph = e ? "≈" + gpaToScoreMid(e.gpa) : "0–100";
      return '<input class="score" type="number" min="0" max="100" step="0.1" inputmode="decimal" ' +
        'data-key="' + key + '" value="' + v + '" placeholder="' + ph + '" aria-label="' + c.name + ' 百分制成绩">';
    }
    let opts = '<option value="">—</option>';
    GPA_VALUES.forEach(function (g) {
      const sel = e && e.gpa === g ? " selected" : "";
      opts += '<option value="' + g.toFixed(1) + '"' + sel + '>' + (g === 0 ? "0.0（挂科）" : g.toFixed(1)) + '</option>';
    });
    return '<select class="gpa' + (e ? "" : " empty") + '" data-key="' + key + '" aria-label="' + c.name + ' 绩点">' + opts + "</select>";
  }

  function hintText(c) {
    const e = state.entries[c._key];
    if (e && e.gpa === 0) return "挂科";
    if (state.mode === "score") {
      if (!e) return "自动换算";
      const k = kaInfo(e);
      return "绩点 " + e.gpa.toFixed(1) + (k ? " · 卡绩 " + k.gap.toFixed(1) : "");
    }
    return "<span class='col-score'>" + (e ? SCORE_RANGE[e.gpa] + " 分" : "—") + "</span>";
  }

  function buildSemesters() {
    recalcTotal();
    $$("#semesters details.sem").forEach(function (d) {
      openState[d.dataset.sem] = d.open;
    });
    const wrap = $("#semesters");
    wrap.innerHTML = "";

    for (let sem = 1; sem <= 8; sem++) {
      const items = [];
      COURSES.forEach(function (c) { if (c.sem === sem) items.push(c); });
      if (!items.length) continue;

      const counted = items.filter(isCounted);
      const semCr = counted.reduce(function (s, c) { return s + c.credit; }, 0);
      const hasCounted = counted.length > 0;
      const hasVisible = hasCounted || items.some(function (c) {
        return Object.prototype.hasOwnProperty.call(state.overrides, c._key) || !!c.custom;
      });

      const box = document.createElement("details");
      box.className = "sem" + (hasVisible ? "" : " empty-sem");
      box.dataset.sem = sem;
      box.open = openState[sem] != null ? openState[sem] : (sem <= 6 && hasVisible);

      let html = "";
      html += "<summary><div class='sem-title'><b>第 " + sem + " 学期</b><span>" + SEM_LABEL[sem] + "</span></div>" +
        "<div class='sem-meta'>" +
        (hasCounted
          ? "计入 <b>" + fmt(semCr) + "</b> 学分<span class='sem-entered'>· 已录 <b class='sem-done'>0</b> 学分</span><span class='sem-gpa'>· 学期 GPA <b>—</b></span>"
          : (hasVisible ? "<span>未勾选计分课程（可勾选）</span>" : "<span>不计入推免学业成绩</span>")) +
        "</div></summary>";

      html += "<div class='table-scroll'><table class='course'><thead><tr>" +
        "<th>课程</th><th class='num'>学分</th>" +
        "<th class='num col-pct-all'>占推免</th><th class='num'>占学期</th>" +
        "<th>录入</th><th class='hint hide-sm'>对应分数</th>" +
        "</tr></thead><tbody>";

      items.forEach(function (c) {
        const key = c._key;
        const e = state.entries[key];
        const countedRow = isCounted(c);
        const overall = countedRow ? (c.credit / TOTAL * 100) : null;
        const inSem = countedRow ? (c.credit / semCr * 100) : null;
        const tagCls = c.type === "必修" ? "must" : c.type === "限选" ? "limit" : c.type === "实践" ? "prac" : "elec";
        let noteText = "";
        if (!countedRow) {
          noteText = Object.prototype.hasOwnProperty.call(state.overrides, key) && state.overrides[key] === false
            ? "已手动排除，不计入当前 GPA；再点“不计入”可恢复。"
            : (c.note || "");
        }
        const manual = Object.prototype.hasOwnProperty.call(state.overrides, key) || !!c.custom;
        html += "<tr class='" + (countedRow ? "counted" : "no") + (manual ? " manual" : "") + (e ? " filled" : "") + (e && e.gpa === 0 ? " fail" : "") + "' data-key='" + key + "'>" +
          "<td class='name'><div class='cname'><span class='code'>" + (c.code || "本地") + "</span>" +
          "<span class='nm'>" + c.name + "</span><span class='tag " + tagCls + "'>" + c.type + "</span>" +
          "<label class='inc' title='勾选=计入；取消=不计入'><input type='checkbox' class='inc-check' data-key='" + key + "'" + (countedRow ? " checked" : "") + "> 计入</label>" +
          (c.custom ? "<button type='button' class='pill-del' data-key='" + key + "' title='删除这门本地课程'>×</button>" : "") +
          (function () { var k = e && countedRow ? kaInfo(e) : null; return "<span class='tag ka-tag'" + (k ? "" : " hidden") + " title='" + (k ? "距上一档仅差 " + k.gap.toFixed(1) + " 分" : "") + "'>卡绩</span>"; })() + "</div>" +
          (noteText ? "<div class='note-inline'>" + noteText + "</div>" : "") +
          "<div class='meta-m'>" + crText(c.credit) + " 学分" + (countedRow ? " · 占推免 " + overall.toFixed(1) + "%" : "") + "</div>" +
          "</td>" +
          "<td class='num'>" + crText(c.credit) + "</td>" +
          "<td class='num pct col-pct-all" + (countedRow ? " strong" : "") + "'>" + (countedRow ? overall.toFixed(1) + "%" : "—") + "</td>" +
          "<td class='num pct'>" + (countedRow ? inSem.toFixed(1) + "%" : "—") + "</td>" +
          "<td class='input-cell'>" + controlHTML(c) + "</td>" +
          "<td class='hint hide-sm'>" + hintText(c) + "</td>" +
          "</tr>";
      });

      html += "</tbody></table></div>";
      box.innerHTML = html;
      wrap.appendChild(box);
    }
    document.body.classList.toggle("show-all", !!state.showAll);
  }

  /* ---------------- update values ---------------- */
  function update() {
    recalcTotal();
    const r = compute();
    const T = state.target;
    FAIL_COUNT = 0;
    COURSES.forEach(function (c) {
      const e = entryOf(c._key);
      if (e && isCounted(c) && e.gpa === 0) FAIL_COUNT++;
    });

    $("#heroTotal").textContent = fmt(TOTAL);
    $("#heroCount").textContent = countedNow();
    if ($("#langPanel")) $("#langPanel").hidden = state.cohort !== "2026";
    if ($("#engAGradeWrap")) $("#engAGradeWrap").hidden = state.cohort === "2026";
    if ($("#engANote")) $("#engANote").hidden = state.cohort === "2026";
    if ($("#engAGrade")) $("#engAGrade").checked = !!state.engA;
    if ($("#correctIntro")) {
      const intro = {
        "2022": "当前按 <b>2022 级参考科目表：40 门 / 95.5 学分</b>（劳动教育不计，企业实训计入）。点课程名旁的“计入/不计入”可切换；修改只保存在本机。",
        "2024": "当前按 <b>2023/24 推算：97.5 学分</b>（劳动教育计入；国家安全教育默认不计，可在课程表里勾选）。官方表未发布，不能当官方。",
        "2025": "当前按 <b>2025 推算：98.5 学分</b>（劳动教育 + 国家安全教育；国安暂按 1 学分/大一上）。官方表未发布，不能当官方。",
        "2026": "当前按 <b>2026 级真实目录：124 门 / 160 学分</b>。默认不勾选；先在下方选英语级别，再逐门勾选你的思政/物理/专业课程。2026 推免细则未发布，分数仅供参考。"
      };
      $("#correctIntro").innerHTML = intro[state.cohort] || intro["2022"];
    }
    if ($("#add2025")) $("#add2025").style.display = state.cohort === "2026" ? "none" : "";
    if ($("#resetCourses")) $("#resetCourses").textContent = state.cohort === "2026" ? "清空 2026 勾选" : "恢复官方 40 门";
    if ($("#heroSub")) {
      const kind = state.cohort === "2022" ? "参考口径" : (state.cohort === "2026" ? "临时目录（非官方）" : "推算口径（非官方）");
      $("#heroSub").innerHTML = META.major + "专业 · " + cohortLabel() + kind +
        " · <b id='heroTotal'>" + fmt(TOTAL) + "</b> 学分 / <b id='heroCount'>" + countedNow() + "</b> 门课程";
    }
    $("#gpaBaoyan").textContent = r.gpa != null ? r.gpa.toFixed(6) : "—";
    $("#gpaBaoyanSub").textContent = TOTAL > 0
      ? "已录 " + fmt(r.eCr) + " / " + fmt(TOTAL) + " 学分 · " + r.eN + " / " + countedNow() + " 门"
      : "未勾选计分课程 · 目录 " + COURSES.length + " 门";
    $("#barBaoyan").style.width = Math.min(100, r.eCr / TOTAL * 100) + "%";

    if ($("#gpaAll")) {
      if (r.aN > r.eN) {
        $("#gpaAll").textContent = r.allGpa.toFixed(6);
        $("#gpaAllSub").textContent = "含选修、体育等，共 " + fmt(r.aCr) + " 学分";
      } else {
        $("#gpaAll").textContent = "—";
        $("#gpaAllSub").textContent = "录入选修/体育等后显示";
      }
    }

    $("#needGpa").textContent = "—";
    $("#needGpa").style.color = "";

    const R = r.remaining;
    const need = R > 1e-9 ? (T * TOTAL - r.eW) / R : null;
    const maxFinal = R > 0 ? (r.eW + 4 * R) / TOTAL : r.gpa;
    const minFinal = R > 0 ? r.eW / TOTAL : r.gpa;
    const proj37 = R > 0 ? (r.eW + 3.7 * R) / TOTAL : r.gpa;

    if (r.eN === 0) {
      $("#needSub").textContent = TOTAL > 0 ? "剩余 " + fmt(TOTAL) + " 学分" : "请勾选计分课程";
    } else if (R <= 1e-9) {
      $("#needGpa").textContent = r.gpa.toFixed(6);
      $("#needGpa").style.color = r.gpa >= T ? "var(--good)" : "var(--bad)";
      $("#needSub").textContent = "全部课程已录入";
    } else if (need != null && need > 4 + 1e-9) {
      $("#needGpa").textContent = "> 4.0";
      $("#needGpa").style.color = "var(--bad)";
      $("#needSub").textContent = "上限 " + maxFinal.toFixed(6) + "，低于目标";
    } else {
      $("#needGpa").textContent = need.toFixed(3);
      $("#needGpa").style.color = need <= 3.5 ? "var(--good)" : need <= 3.8 ? "var(--warn)" : "var(--bad)";
      $("#needSub").textContent = "剩余 " + fmt(R) + " 学分 / " + r.remainingN + " 门";
    }

    // semester summaries
    $$("#semesters details.sem").forEach(function (d) {
      const sem = Number(d.dataset.sem);
      let cr = 0, w = 0;
      COURSES.forEach(function (c) {
        if (c.sem !== sem) return;
        const e = entryOf(c._key);
        if (!e) return;
        if (isCounted(c)) { cr += c.credit; w += c.credit * e.gpa; }
      });
      const doneEl = $(".sem-done", d), gpaEl = $(".sem-gpa b", d);
      if (doneEl) doneEl.textContent = fmt(cr) ;
      if (gpaEl) gpaEl.textContent = cr > 0 ? (w / cr).toFixed(6) : "—";
    });

    updateVerdict(r, T, need, maxFinal, minFinal, proj37);
    updateAdvice(r, T, need, maxFinal, minFinal, proj37);
  }

  /* ---------------- verdict ---------------- */
  function setVerdict(cls, title, text) {
    if (FAIL_COUNT && cls !== "bad") cls = "warn";
    const v = $("#verdict");
    v.className = "verdict " + cls;
    $("#verdictIcon").textContent = cls === "good" ? "✓" : cls === "bad" ? "!" : cls === "warn" ? "!" : "i";
    $("#verdictTitle").textContent = title;
    let failNote = "";
    if (FAIL_COUNT >= 2) failNote = "注意：已录入 " + FAIL_COUNT + " 门计分课挂科，超过普通推荐允许的 1 门，资格不保。";
    else if (FAIL_COUNT === 1) failNote = "注意：已录入 1 门计分课挂科，在允许的 1 门内，但须在推免前重修通过；排名仍按第一次成绩。";
    $("#verdictText").textContent = failNote + text;
  }

  function updateVerdict(r, T, need, maxFinal, minFinal, proj37) {
    if (r.eN === 0) {
      setVerdict("", "先录入成绩", "从下面任意学期开始，按课程填入绩点（或切到百分制），GPA 与剩余目标会实时更新。");
      return;
    }
    if (r.remaining <= 1e-9) {
      if (r.gpa >= T) setVerdict("good", "目标已达成", countedNow() + " 门计分课程已全部录入，最终学业 GPA " + r.gpa.toFixed(6) + "，达到目标 " + T.toFixed(2) + "。仍需注意挂科上限（普通推荐最多允许 1 门，须重修通过）与综合排名。");
      else setVerdict("bad", "未达目标", "全部录入后 GPA " + r.gpa.toFixed(6) + "，低于目标 " + T.toFixed(2) + "。可争取素质加分（上限 0.4）或关注备选/专项计划。");
      return;
    }
    const rn = r.remainingN;
    const t = function (n) { return n == null ? "—" : n.toFixed(3); };
    const t6 = function (n) { return n == null ? "—" : n.toFixed(6); };
    if (maxFinal < CUTOFF - 1e-9) {
      setVerdict("bad", "大概率无法保研", "按当前已修成绩，剩余 " + fmt(r.remaining) + " 学分即使全部 4.0，最终最高也只有 " + t6(maxFinal) + "，低于 2026 年最低门槛 " + CUTOFF.toFixed(6) + "。除非名额大幅增加或走专项通道，大概率无法保研。");
      return;
    }
    if (maxFinal < T - 1e-9) {
      setVerdict("warn", "达不到设定目标", "已录 " + fmt(r.eCr) + " 学分，GPA " + r.gpa.toFixed(6) + "；剩余 " + fmt(r.remaining) + " 学分即使全部 4.0，最终最高 " + t6(maxFinal) + "，低于目标 " + T.toFixed(2) + "，但仍高于 2026 线 " + CUTOFF.toFixed(6) + "，按去年线仍有机会，只是达不到你设的目标。");
      return;
    }
    if (need <= 0) {
      setVerdict("good", "目标已锁定", "已录 GPA " + r.gpa.toFixed(6) + "，剩余 " + fmt(r.remaining) + " 学分；即使剩余全部 0 分，最终仍有 " + t6(minFinal) + " ≥ 目标 " + T.toFixed(2) + "。");
      return;
    }
    if (need <= 3.5) {
      setVerdict("", "进度良好", "剩余 " + fmt(r.remaining) + " 学分（" + rn + " 门）需平均 " + t(need) + "；按剩余 3.7 估算，最终 " + t6(proj37) + "。");
    } else if (need <= 3.8) {
      setVerdict("warn", "需要冲刺", "剩余 " + fmt(r.remaining) + " 学分（" + rn + " 门）需平均 " + t(need) + "，高于“良好”区间；每一门 3.3 以下都会明显拉低结果。");
    } else {
      setVerdict("warn", "压力较大", "剩余 " + fmt(r.remaining) + " 学分需平均 " + t(need) + "，接近满绩。建议同时准备素质加分与备选方案。");
    }
  }

  /* ---------------- advice ---------------- */
  function updateAdvice(r, T, need, maxFinal, minFinal, proj37) {
    const ul = $("#adviceList");
    const items = [];
    const t = n => (n == null ? "—" : n.toFixed(3));
    const t6 = n => (n == null ? "—" : n.toFixed(6));
    const g = r.gpa != null ? r.gpa.toFixed(6) : "—";
    const rank = estimateRank(r.gpa);

    const ref0 = META.reference[0];
    const hist = META.reference.slice(1).map(function (x) { return x.year + " 年 " + x.minGpa.toFixed(6); }).join("；");
    if (r.eN === 0) {
      items.push({ html: "本页按 <b>" + META.plan + "</b> 收录 " + countedNow() + " 条计分记录，共 <b>" + fmt(TOTAL) + " 学分</b>" + (META.enterpriseCode ? "（企业实训切换后为 96.0 / 97.5）" : "") + "。先录大一、大二课程即可看到趋势。" });
      items.push({ html: "计分范围：必修课（含实践），<b>不含</b>体育、军事教育、大学英语Ⅰ/Ⅱ、限选课与专业选修。" });
      items.push({ html: "目标默认取 2026 年" + META.major + "实际录取线 <b>" + CUTOFF.toFixed(6) + "</b>" + (hist ? "；此前 " + hist : "") + "。建议目标留 0.02–0.05 余量。" });
    } else {
      const failed = [];
      COURSES.forEach(function (c) {
        const e = entryOf(c._key);
        if (e && e.gpa === 0 && isCounted(c)) failed.push(c.name);
      });
      if (failed.length) {
        items.push({
          cls: "bad",
          html: "<b>挂科预警</b>：" + failed.slice(0, 3).join("、") + (failed.length > 3 ? " 等 " + failed.length + " 门" : "") +
            " 已按 0 绩点计入。" + (failed.length >= 2
              ? "已超过普通推荐允许的 1 门，普通推荐资格不保。"
              : "在允许的 1 门内，但必须在推免前重修通过；排名仍按第一次成绩（0 绩点），GPA 损失很大。")
        });
      }
      const ka = [];
      COURSES.forEach(function (c) {
        const e = entryOf(c._key);
        if (!e || !isCounted(c) || e.gpa <= 0) return;
        const k = kaInfo(e);
        if (k) ka.push({ c: c, e: e, k: k });
      });
      if (ka.length) {
        const gain = ka.reduce(function (s, x) { return s + (x.k.up - x.e.gpa) * x.c.credit; }, 0) / TOTAL;
        const eg = ka.slice(0, 3).map(function (x) { return x.c.name + " " + x.e.score.toFixed(1) + "→" + x.k.up.toFixed(1); }).join("、");
        items.push({
          cls: "warn",
          html: "<b>卡绩提醒</b>：" + ka.length + " 门计分课距上一档不足 1 分（" + eg + "），合计约影响 GPA <b>" + gain.toFixed(6) + "</b>。期末前把这几门拉过线，收益最直接。"
        });
      }
      items.push({
        html: "<b>现状</b>：已录 " + r.eN + "/" + countedNow() + " 门，覆盖 " + fmt(r.eCr) + " 学分（" + pct(r.eCr / TOTAL) + "），加权 GPA <b>" + g + "</b>。" +
          (rank ? "按 2026 届分布约对应第 <b>" + rank + "</b> / " + META.reference[0].cohort + " 名（前 " + pct(rank / META.reference[0].cohort) + "）。" : "")
      });

      if (r.remaining > 1e-9) {
        items.push({
          html: "<b>目标 " + T.toFixed(2) + "</b>：剩余 " + fmt(r.remaining) + " 学分（" + r.remainingN + " 门）需平均 <b class='" + (need > 3.8 ? "neg" : "pos") + "'>" + t(need) + "</b>。" +
            "若剩余全 4.0，最终 " + t6(maxFinal) + "；若按 3.7，最终 " + t6(proj37) + "。"
        });
        const needAt = function (b) { return ((T - b) * TOTAL - r.eW) / r.remaining; };
        items.push({
          html: "<b>加分杠杆</b>：素质加分上限 0.4。若拿 0.1 加分，等效学业线降至 " + (T - 0.1).toFixed(2) + "，剩余需平均 <b>" + t(needAt(0.1)) + "</b>；拿 0.2 则需 <b>" + t(needAt(0.2)) + "</b>。"
        });
      } else {
        items.push({ html: "<b>目标 " + T.toFixed(2) + "</b>：" + countedNow() + " 门已全部录入，最终 GPA <b>" + g + "</b>，与目标相差 <b>" + (r.gpa - T >= 0 ? "+" : "") + (r.gpa - T).toFixed(6) + "</b>。" });
      }

      items.push({
        html: "<b>参考线</b>：2026 年" + META.major + "拟推荐 <b>" + ref0.admitted + "</b> 人（" + ref0.cohort + " 人的前 " + ref0.quotaPct + "%），最低学业 GPA <b>" + ref0.minGpa.toFixed(6) + "</b>" + (hist ? "；" + hist : "") + "。"
      });
      items.push({
        html: "<b>风险</b>：普通推荐允许最多 <b>1 门</b>必修/限选不及格，但须在推免前重修通过；排名仍按<b>第一次成绩</b>，2 门及以上资格不保。名额、加分细则每年调整；外语需四级 425+（或校内必修英语均分 75+）。"
      });
      if (maxFinal < CUTOFF - 1e-9) {
        items.push({ cls: "bad", html: "<b>结论</b>：按当前成绩，即使剩余课程全部满绩，最终最高也只有 " + t6(maxFinal) + "，低于 2026 年最低门槛 " + CUTOFF.toFixed(6) + "，<b>大概率无法保研</b>。优先确认专项/补偿计划等通道，同时准备考研或其他出路。" });
      } else if (maxFinal < T - 1e-9) {
        items.push({ cls: "warn", html: "<b>结论</b>：靠剩余课程达不到目标 " + T.toFixed(2) + "，但最高 " + t6(maxFinal) + " 仍高于 2026 线 " + CUTOFF.toFixed(6) + "，按去年线仍有机会，只是达不到目标；重点看当年名额和加分。" });
      } else if (need > 3.8) {
        items.push({ cls: "warn", html: "<b>结论</b>：剩余课程需要接近满绩，容错很低。建议锁定 3.7+ 的课程策略，同时用加分与竞赛提高综合排名。" });
      } else if (need <= 3.5) {
        items.push({ cls: "hot", html: "<b>结论</b>：按当前节奏，保持剩余课程 3.5 左右即可达到目标；重点防挂科、防低分必修。" });
      }
    }

    ul.innerHTML = items.map(function (x) {
      return "<li class='" + (x.cls || "") + "'>" + x.html + "</li>";
    }).join("");
  }

  /* ---------------- events ---------------- */
  function onInput(e) {
    const el = e.target;
    if (el.matches("input.inc-check")) {
      const key = el.dataset.key;
      state.overrides[key] = el.checked;
      rebuildCourses();
      buildSemesters();
      update();
      updateIssue();
      save();
      return;
    }
    if (!el.matches("select.gpa, input.score")) return;
    const key = el.dataset.key;
    const course = COURSES.find(function (c) { return c._key === key; });

    if (el.matches("select.gpa")) {
      const v = el.value;
      if (v === "") delete state.entries[key];
      else state.entries[key] = { gpa: Number(v), score: null };
      el.classList.toggle("empty", v === "");
    } else {
      const raw = el.value.trim();
      if (raw === "") {
        delete state.entries[key];
      } else {
        const s = Number(raw);
        const g = scoreToGpa(s);
        if (g == null) return;
        state.entries[key] = { gpa: g, score: s };
      }
    }

    const tr = el.closest("tr");
    if (tr) {
      tr.classList.toggle("filled", !!state.entries[key]);
      tr.classList.toggle("fail", !!(state.entries[key] && state.entries[key].gpa === 0));
      const hint = $(".hint", tr);
      if (hint && course) hint.textContent = hintText(course).replace(/<[^>]+>/g, "");
      const ka = $(".ka-tag", tr);
      if (ka && course) {
        const k = isCounted(course) ? kaInfo(state.entries[key]) : null;
        ka.hidden = !k;
        ka.title = k ? "距上一档仅差 " + k.gap.toFixed(1) + " 分" : "";
      }
    }
    update();
    save();
  }

  function setMode(mode) {
    if (mode === state.mode) return;
    state.mode = mode;
    $$(".seg button").forEach(function (b) { b.classList.toggle("active", b.dataset.mode === mode); });
    buildSemesters();
    update();
    save();
  }

  function fillDemo() {
    state.entries = {};
    const pattern = [3.7, 4.0, 3.3, 3.7, 3.0, 3.7, 3.3, 4.0, 3.7, 3.0];
    let k = 0;
    COURSES.forEach(function (c) {
      if (!isCounted(c) || c.sem > 4) return;
      state.entries[c._key] = { gpa: pattern[k % pattern.length], score: null };
      k++;
    });
    buildSemesters();
    update();
    save();
  }

  function resetAll() {
    state.entries = {};
    state.engA = false;
    buildSemesters();
    update();
    save();
  }

  function exportCSV() {
    const rows = [["学期", "课程代码", "课程名称", "类型", "学分", "计入推免", "绩点", "百分制"]];
    COURSES.forEach(function (c) {
      const e = state.entries[c._key];
      rows.push([c.sem, c.code || "", c.name, c.type, crText(c.credit), isCounted(c) ? "是" : "否",
        e ? e.gpa.toFixed(1) : "", e && e.score != null ? e.score : ""]);
    });
    const csv = "\ufeff" + rows.map(function (r) {
      return r.map(function (x) { return '"' + String(x).replace(/"/g, '""') + '"'; }).join(",");
    }).join("\r\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    const d = new Date();
    const ds = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    a.download = "吉大" + META.major + "_GPA_" + ds + ".csv";
    document.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  }

  /* ---------------- 纠正科目 ---------------- */
  function toggleCourse(key) {
    const c = COURSES.find(function (x) { return x._key === key; });
    if (!c) return;
    state.overrides[key] = !isCounted(c);
    rebuildCourses();
    buildSemesters();
    update();
    updateIssue();
    save();
  }

  function addCustomCourse(name, credit, sem, type) {
    const key = "u" + Date.now() + "_" + Math.floor(Math.random() * 1000);
    state.custom.push({ key: key, name: name, credit: credit, sem: sem, type: type });
    rebuildCourses();
    buildSemesters();
    update();
    updateIssue();
    save();
  }

  function removeCustomCourse(key) {
    state.custom = state.custom.filter(function (c) { return c.key !== key; });
    delete state.entries[key];
    delete state.overrides[key];
    rebuildCourses();
    buildSemesters();
    update();
    updateIssue();
    save();
  }

  function isLangCourse(c) {
    return /英语|日语|德语|法语|俄语|西班牙/.test((c.note || "") + " " + c.name);
  }

  function findCourse(name, notePrefix) {
    return COURSES.find(function (c) {
      return c.name === name && (c.note || "").indexOf(notePrefix) === 0;
    });
  }

  function checkCourse(c) {
    if (c) state.overrides[c._key] = true;
  }

  function setEngA(on) {
    state.engA = on;
    ["911105", "911106"].forEach(function (code) {
      const c = BASE_COURSES.find(function (x) { return x.code === code; });
      if (!c) return;
      if (on) {
        state.entries[c._key] = { gpa: 4.0, score: null, auto: true };
      } else if (state.entries[c._key] && state.entries[c._key].auto) {
        delete state.entries[c._key];
      }
    });
    buildSemesters();
    update();
    save();
  }

  function applyLanguage() {
    const lang = $("#langSelect").value;
    const level = $("#engLevel").value;
    const ext = $("#engExt").value;
    const st = $("#cohortStatus");

    COURSES.forEach(function (c) {
      if (isLangCourse(c)) state.overrides[c._key] = false;
    });

    if (lang === "英语") {
      if (level === "A" || level === "B") {
        checkCourse(findCourse("综合英语", "英语" + level + "级综合"));
        checkCourse(findCourse("学科英语素养", "英语" + level + "级学科英语素养"));
        if (ext) checkCourse(findCourse(ext, "英语" + level + "级拓展"));
      } else if (level === "P") {
        checkCourse(findCourse("综合英语预备级", "英语预备级"));
        checkCourse(findCourse("综合英语Ⅰ", "英语预备级"));
        checkCourse(findCourse("综合英语Ⅱ", "英语预备级"));
      }
      if (st) st.textContent = level === "EX"
        ? "英语免修：未勾选英语课；如学校要求仍修某门，请手动勾选。"
        : level
          ? "已按英语 " + (level === "P" ? "预备级" : level + " 级") + (ext ? " + " + ext : "（拓展课未选）") + " 自动勾选；可再手动调整。"
          : "请选择英语级别（A / B / 预备级 / 免修）。";
    } else {
      ["Ⅰ", "Ⅱ", "Ⅲ"].forEach(function (n) {
        checkCourse(findCourse("大学" + lang + n, "大学" + lang));
      });
      if (st) st.textContent = "已按外语 " + lang + " 自动勾选 I/II/III；英语课已取消勾选。";
    }

    rebuildCourses();
    buildSemesters();
    update();
    updateIssue();
    save();
  }

  function applyCohort(code) {
    state.cohort = code;
    state.custom.forEach(function (c) { delete state.entries[c.key]; delete state.overrides[c.key]; });
    state.custom = [];
    state.overrides = {};
    if (code === "2026" && window.GPA_2026_CATALOG) {
      state.custom = (window.GPA_2026_CATALOG.courses || []).map(function (c) {
        return { key: c.key, name: c.name, credit: c.credit, sem: c.sem, type: c.type, note: c.note || "" };
      });
      state.custom.forEach(function (c) { state.overrides[c.key] = false; });
      rebuildCourses();
      buildSemesters();
      update();
      updateIssue();
      save();
      const st0 = $("#cohortStatus");
      if (st0) st0.textContent = "已切换 2026 级临时目录：124 门课程全部列出、默认不勾选；请按你的英语级别和思政/物理实际课程勾选。2026 细则未发布，分数线不适用。";
      return;
    }
    if (code !== "2022") {
      BASE_COURSES.forEach(function (c) { if (c.code === "LD2001") state.overrides[c._key] = true; });
    }
    if (code === "2024" || code === "2025" || code === "2026") {
      state.custom.push({ key: "u2025natsec", name: "国家安全教育", credit: 1, sem: 1, type: "必修" });
      if (code === "2024") state.overrides["u2025natsec"] = false; // 2024 不确定，默认不计，勾选可计入
    }
    rebuildCourses();
    buildSemesters();
    update();
    updateIssue();
    save();
    const st = $("#cohortStatus");
    if (st) st.textContent = code === "2022"
      ? "已切换 2022 级参考口径：40 门 / 95.5（旧规则，劳动教育不计；仅参考）。"
      : code === "2024"
        ? "已切换 2023/24 级推算口径：劳动教育计入；国家安全教育不确定，默认不计，可在下方勾选。总学分 97.5（勾选后 98.5）；官方表未发布。"
        : code === "2025"
          ? "已切换 2025 级推算口径：劳动教育 + 国家安全教育（暂按 1 学分/大一上，待 2025 培养方案核对），98.5；官方表未发布，不能当官方。"
          : "已切换 2026 级临时版：基于 2025 推算（98.5），思政/物理课程变化未建模；请用下方勾选/添加课程按实际调整。";
  }

  function resetCourses() {
    state.cohort = "2022";
    state.custom.forEach(function (c) { delete state.entries[c.key]; delete state.overrides[c.key]; });
    state.custom = [];
    state.overrides = {};
    rebuildCourses();
    buildSemesters();
    update();
    updateIssue();
    save();
  }

  function buildReportText() {
    const counted = COURSES.filter(isCounted);
    const excluded = COURSES.filter(function (c) { return !isCounted(c); });
    const r = compute();
    const lines = [];
    lines.push("# 科目纠正报告");
    lines.push("");
    lines.push("- 专业：" + META.major + " " + cohortLabel());
    lines.push("- 官方口径：" + (state.cohort === "2026"
      ? "2026级软件工程主修培养方案（160学分，124门目录；推免细则未发布）"
      : OFFICIAL));
    lines.push("- 当前计分：" + counted.length + "门 / " + fmt(TOTAL) + "学分");
    lines.push("- 已录入：" + r.eN + "门 / " + fmt(r.eCr) + "学分，GPA " + (r.gpa != null ? r.gpa.toFixed(6) : "—"));
    lines.push("");
    lines.push("## 计分课程（" + counted.length + "）");
    counted.forEach(function (c, i) {
      lines.push((i + 1) + ". " + SEM_LABEL[c.sem] + " | " + c.name + " | " + crText(c.credit) + (c.code ? " | " + c.code : ""));
    });
    if (excluded.length) {
      lines.push("");
      lines.push("## 当前排除的课程（" + excluded.length + "）");
      excluded.forEach(function (c) {
        lines.push("- " + SEM_LABEL[c.sem] + " | " + c.name + " | " + crText(c.credit));
      });
    }
    if (state.custom.length) {
      lines.push("");
      lines.push("## 本地新增课程（" + state.custom.length + "）");
      state.custom.forEach(function (c) {
        lines.push("- " + SEM_LABEL[c.sem] + " | " + c.name + " | " + crText(c.credit) + " | " + c.type);
      });
    }
    lines.push("");
    lines.push("说明：由 JLU GPA 页面生成，供学院口径核对。");
    return lines.join("\n");
  }

  function updateIssue() {
    const link = $("#issueLink");
    if (!link) return;
    if (!META.issueRepo) { link.style.display = "none"; return; }
    const title = "[科目纠正] " + META.major + cohortLabel() + " " + countedNow() + "门/" + fmt(TOTAL) + "学分";
    link.href = META.issueRepo + "/issues/new?title=" + encodeURIComponent(title) + "&body=" + encodeURIComponent(buildReportText());
  }

  function copyReport() {
    const text = buildReportText();
    const box = $("#reportBox");
    const status = $("#reportStatus");
    updateIssue();
    if (box) { box.hidden = false; box.value = text; }
    const done = function (msg) { if (status) status.textContent = msg; };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        done("已复制到剪贴板；可直接点“提交 GitHub issue”，或粘贴到学院反馈。");
      }).catch(function () {
        if (box) { box.select(); document.execCommand("copy"); }
        done("已选中报告，按 Cmd/Ctrl+C 复制。");
      });
    } else {
      if (box) { box.select(); document.execCommand("copy"); }
      done("已选中报告，按 Cmd/Ctrl+C 复制。");
    }
  }

  /* ---------------- static sections ---------------- */
  function buildStatic() {
    // reference table
    const tb = $("#refBody");
    tb.innerHTML = META.reference.map(function (x) {
      const parts = [];
      if (x.line30 != null) parts.push((x.lineLabel || "前 30% 线") + " " + x.line30.toFixed(6));
      if (x.quotaPct != null) parts.push("名额约 " + x.quotaPct + "%");
      const note = parts.length ? parts.join("；") : "—";
      return "<tr class='" + (x.year === 2026 ? "hl" : "") + "'><td>" + x.year + "</td><td>" + x.admitted +
        "</td><td>" + (x.cohort || "—") + "</td><td><b>" + x.minGpa.toFixed(6) + "</b></td><td>" + note + "</td></tr>";
    }).join("");

    // rules
    $("#ruleList").innerHTML = META.rules.map(function (r) { return "<li>" + r + "</li>"; }).join("");

    // conversion table
    const conv = [
      ["90–100", "4.0"], ["87–89.9", "3.7"], ["84–86.9", "3.3"], ["80–83.9", "3.0"],
      ["77–79.9", "2.7"], ["74–76.9", "2.3"], ["70–73.9", "2.0"], ["67–69.9", "1.7"],
      ["64–66.9", "1.3"], ["60–63.9", "1.0"], ["60 以下", "0（挂科）"]
    ];
    $("#convTable tbody").innerHTML = conv.map(function (r) {
      return "<tr><td>" + r[0] + " 分</td><td>" + r[1] + "</td></tr>";
    }).join("");

    $("#updated").textContent = "数据更新 " + META.generated;
  }

  /* ---------------- init ---------------- */
  function init() {
    load();
    rebuildCourses();
    buildStatic();

    $("#target").value = state.target.toFixed(2);
    if ($("#showAll")) $("#showAll").checked = state.showAll;
    $$(".seg button").forEach(function (b) { b.classList.toggle("active", b.dataset.mode === state.mode); });

    buildSemesters();
    update();

    $("#semesters").addEventListener("change", onInput);
    $("#semesters").addEventListener("input", function (e) {
      if (e.target.matches("input.score")) onInput(e);
    });

    $$(".seg button").forEach(function (b) {
      b.addEventListener("click", function () { setMode(b.dataset.mode); });
    });

    $("#target").addEventListener("input", function () {
      let v = Number(this.value);
      if (!isFinite(v)) return;
      v = Math.max(0, Math.min(4, v));
      state.target = v;
      update();
      save();
    });

    $("#presets").addEventListener("click", function (e) {
      const b = e.target.closest("button[data-t]");
      if (!b) return;
      state.target = Number(b.dataset.t);
      $("#target").value = state.target.toFixed(2);
      update();
      save();
    });

    if ($("#showAll")) {
      $("#showAll").addEventListener("change", function () {
        state.showAll = this.checked;
        document.body.classList.toggle("show-all", state.showAll);
        save();
      });
    }

    if ($("#entToggle")) {
      $("#entToggle").addEventListener("change", function () {
        state.includeEnterprise = this.checked;
        buildSemesters();
        update();
        save();
      });
    }

    $("#demoBtn").addEventListener("click", fillDemo);
    $("#resetBtn").addEventListener("click", resetAll);
    $("#csvBtn").addEventListener("click", exportCSV);

    $("#semesters").addEventListener("click", function (e) {
      const del = e.target.closest(".pill-del");
      if (del) { removeCustomCourse(del.dataset.key); }
    });

    if ($("#engAGrade")) $("#engAGrade").addEventListener("change", function () { setEngA(this.checked); });
    if ($("#applyLang")) $("#applyLang").addEventListener("click", applyLanguage);
    if ($("#langSelect")) {
      $("#langSelect").addEventListener("change", function () {
        const eng = this.value === "英语";
        $("#engLevel").disabled = !eng;
        $("#engExt").disabled = !eng;
      });
    }

    if ($("#addCourseForm")) {
      $("#addCourseForm").addEventListener("submit", function (e) {
        e.preventDefault();
        const name = $("#addName").value.trim();
        const credit = Number($("#addCredit").value);
        const sem = Number($("#addSem").value);
        const type = $("#addType").value;
        if (!name || !isFinite(credit) || credit <= 0) return;
        addCustomCourse(name, credit, sem, type);
        this.reset();
      });
    }
    $$("[data-cohort]").forEach(function (btn) {
      btn.addEventListener("click", function () { applyCohort(btn.dataset.cohort); });
    });

    if ($("#add2025")) {
      $("#add2025").addEventListener("click", function () { applyCohort("2025"); });
    }
    if ($("#resetCourses")) $("#resetCourses").addEventListener("click", function () {
      if (state.cohort === "2026") applyCohort("2026"); else resetCourses();
    });
    if ($("#reportBtn")) $("#reportBtn").addEventListener("click", copyReport);
    if ($("#issueLink")) {
      $("#issueLink").addEventListener("click", function () {
        updateIssue();
      });
    }

    updateIssue();

    const q = new URLSearchParams(location.search).get("cohort");
    if (q && COHORT_LABEL[q]) applyCohort(q);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
