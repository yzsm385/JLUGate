/* 首页选择逻辑 · 2026-11-14 版
 * 相比 landing-20261113.js 的变化：
 *   1. App 深链支持 #college / #collegeName / #sid / #year / #major：
 *      App 认出学院后直接预填，并把焦点放到「专业」，用户只需选专业。
 *   2. 学院中文名按「去掉学院/学部/系 + 常见别名」匹配（外国语、口腔）。
 *   3. 深链只带年级时也能预填，不再当成识别失败。
 *   4. 其余年级记忆、同码多院候选、方案回滚逻辑保持不变。
 */
(function () {
  var refreshed = null;
  try {
    refreshed = JSON.parse(sessionStorage.getItem("GPA_INDEX_REFRESH") || "null");
    sessionStorage.removeItem("GPA_INDEX_REFRESH");
  } catch (e) { /* ignore */ }
  var data = refreshed || window.GPA_PLAN_INDEX;
  var sid = window.STUDENT_ID_PREFIXES;
  var collegeSel = document.getElementById("collegeSel");
  var majorSel = document.getElementById("majorSel");
  var yearSel = document.getElementById("yearSel");
  var goBtn = document.getElementById("goBtn");
  var preview = document.getElementById("planPreview");
  var hint = document.getElementById("pickerHint");
  var accountInput = document.getElementById("accountInput");
  var detectBtn = document.getElementById("detectBtn");
  var manualBtn = document.getElementById("manualBtn");
  var accountResult = document.getElementById("accountResult");
  var refreshBtn = document.getElementById("refreshBtn");
  var importBtn = document.getElementById("importBtn");
  var importFile = document.getElementById("importFile");

  if (!data || !data.colleges) {
    if (hint) hint.textContent = "专业索引没有加载成功；请确认 data/plans-index.js 存在。";
    return;
  }

  /* ===== 年级记忆（landing 与 plan 页共用同一组 key） ===== */
  var YEAR_KEY = "jlu-plan-entry-year";
  var YEAR_AUTO_KEY = "jlu-plan-entry-year-auto";
  var YEAR_SRC_KEY = "jlu-plan-entry-year-src";

  function readStoredYear() {
    try {
      var y = Number(localStorage.getItem(YEAR_KEY));
      return (y >= 2000 && y <= 2040) ? y : null;
    } catch (e) { return null; }
  }
  function storeYear(year, auto, src) {
    try {
      localStorage.setItem(YEAR_KEY, String(year));
      localStorage.setItem(YEAR_AUTO_KEY, auto ? "1" : "0");
      if (src) localStorage.setItem(YEAR_SRC_KEY, src);
    } catch (e) { /* ignore */ }
  }
  function clearStoredYear() {
    try {
      localStorage.removeItem(YEAR_KEY);
      localStorage.removeItem(YEAR_AUTO_KEY);
      localStorage.removeItem(YEAR_SRC_KEY);
    } catch (e) { /* ignore */ }
  }

  var colleges = data.colleges.slice().sort(function (a, b) {
    return (a.code || "").localeCompare(b.code || "", "zh-CN", { numeric: true });
  });
  var byCode = {};
  colleges.forEach(function (c) { byCode[String(c.code).toLowerCase()] = c; });

  var groups = [];          // 当前学院的专业组（同名专业跨年份合并）
  var desiredYear = null;   // 生效中的入学年份（识别 / 记忆 / 手选）
  var yearAuto = false;     // 年级是否来自学号自动识别
  var yearSrc = "";         // 年级来源：sid=完整学号 sid4=4位学号 manual=手选
  var detectedLabel = "";

  colleges.forEach(function (c) {
    var o = document.createElement("option");
    o.value = c.code;
    o.textContent = (c.code ? c.code + " · " : "") + c.name + "（" + c.majors.length + "）";
    collegeSel.appendChild(o);
  });
  if (yearSel) {
    [2026, 2025, 2024, 2023, 2022].forEach(function (y) {
      var o = document.createElement("option");
      o.value = String(y);
      o.textContent = y + " 级";
      yearSel.appendChild(o);
    });
  }

  function currentCollege() { return byCode[String(collegeSel.value).toLowerCase()] || null; }

  function currentGroup() {
    return groups.find(function (g) { return g.major === majorSel.value; }) || null;
  }

  function groupMajors(c) {
    var map = {};
    var out = [];
    c.majors.forEach(function (m) {
      if (!map[m.major]) {
        map[m.major] = { major: m.major, plans: [] };
        out.push(map[m.major]);
      }
      map[m.major].plans.push(m);
    });
    out.forEach(function (g) {
      g.plans.sort(function (a, b) {
        return (b.year - a.year) || (b.courses - a.courses);
      });
    });
    out.sort(function (a, b) { return a.major.localeCompare(b.major, "zh-CN"); });
    return out;
  }

  /* 没有确定年级时才取最新；有年级取 ≤ 年级的最近一级 */
  function pickPlan(group) {
    if (!group || !group.plans.length) return null;
    if (desiredYear) {
      var older = group.plans.filter(function (p) { return p.year <= desiredYear; });
      if (older.length) return older[0]; // 已按年份降序，取最靠近的 ≤ 入学年
      return null;
    }
    return group.plans[0];
  }

  function yearText(plan) {
    if (!desiredYear) return "未选年级，默认 " + plan.year + " 级方案";
    if (plan.year === desiredYear) return desiredYear + " 级方案";
    return desiredYear + " 级没有方案，已回滚到 " + plan.year + " 级";
  }

  function describeYear() {
    if (!desiredYear) return "未选年级：按最新方案（多为 2026 级）。";
    var how = yearAuto ? "（从学号识别）" : "（手动选择）";
    return "按 " + desiredYear + " 级匹配方案" + how + "；库里没有对应方案时向更早年份回滚。";
  }

  function syncYearSel() {
    if (!yearSel) return;
    yearSel.value = desiredYear ? String(desiredYear) : "";
    yearSel.title = describeYear();
  }

  function setYear(year, auto, src) {
    desiredYear = year;
    yearAuto = !!auto;
    yearSrc = src || (auto ? "sid" : "manual");
    if (year) storeYear(year, yearAuto, yearSrc); else clearStoredYear();
    syncYearSel();
    fillMajors();
    showPreview();
  }

  function fillMajors() {
    var c = currentCollege();
    groups = c ? groupMajors(c) : [];
    majorSel.innerHTML = "";
    preview.hidden = true;
    goBtn.disabled = true;
    if (!c) {
      majorSel.disabled = true;
      majorSel.innerHTML = "<option value=''>先选学院</option>";
      hint.textContent = describeYear() + " 先选学院，再选专业。";
      return;
    }
    majorSel.disabled = false;
    majorSel.innerHTML = "<option value=''>请选择专业</option>";
    groups.forEach(function (g) {
      var o = document.createElement("option");
      o.value = g.major;
      var years = g.plans.map(function (p) { return p.year; }).sort();
      o.textContent = g.major + " · " + years.join("/") + "级 · " + g.plans[0].courses + " 门";
      majorSel.appendChild(o);
    });
    hint.textContent = c.name + "：共 " + groups.length + " 个专业；" + describeYear();
  }

  function showPreview() {
    var g = currentGroup();
    if (!g) { preview.hidden = true; goBtn.disabled = true; return; }
    var plan = pickPlan(g);
    if (!plan) {
      goBtn.disabled = true;
      preview.hidden = false;
      var years = g.plans.map(function (p) { return p.year; }).sort();
      preview.innerHTML = "<div class='preview-main'><b>" + g.major + "</b><span class='warn'>暂无 " +
        (desiredYear || "") + " 级及更早方案</span></div>" +
        "<div class='preview-note'>数据库里这个专业只有 " + years.join(" / ") +
        " 级；按“向更早年份回滚”的规则，不能拿更晚的方案顶替。可在上方「年级」改选库里有的年份，或补对应年份的培养方案。</div>";
      return;
    }
    var older = g.plans.filter(function (p) { return p.year <= plan.year && p.year < plan.year; });
    var alt = g.plans.filter(function (p) { return p.year > plan.year; });
    var altText = alt.length ? "；库里还有 " + alt.map(function (p) { return p.year; }).join("/") + " 级（上方年级处可改）" : "";
    goBtn.disabled = false;
    preview.hidden = false;
    var special = plan.route.indexOf("software.html") === 0 || plan.route.indexOf("computer.html") === 0;
    preview.innerHTML =
      "<div class='preview-main'><b>" + g.major + " · " + plan.year + " 级</b>" +
      "<span>" + (special ? "专门版" : plan.year + " 主修通用目录") + "</span></div>" +
      "<div class='preview-meta'>" + plan.courses + " 门课程 · 计划 " + plan.credits +
      " 学分 · " + yearText(plan) +
      (older.length ? " · 可回退 " + older.map(function (p) { return p.year; }).join("/") + " 级" : "") +
      altText + "</div>" +
      "<div class='preview-note'>" + (special
        ? "进入后可在专门版内切换年份口径（该版自带 2022–2026 切换）。"
        : "按你选的年级进入对应课程目录；勾选与成绩按方案分开保存，切换年级互不覆盖。") + "</div>";
  }

  function say(html) {
    if (!accountResult) return;
    accountResult.hidden = false;
    accountResult.innerHTML = html;
  }

  function chooseCollege(code, note) {
    var c = byCode[String(code).toLowerCase()];
    if (!c) {
      say("识别到代码 <b>" + code + "</b>，但数据库里没有这个学院的方案；请手动选择。");
      return false;
    }
    collegeSel.value = c.code;
    fillMajors();
    say(note + "<br>已预填：<b>" + (code ? code + " · " : "") + c.name + "</b>。专业还需要你选择。");
    focusMajor();
    return true;
  }

  /* 把焦点放到「专业」下拉：深链预填学院后，下一步本来就是选专业。 */
  function focusMajor() {
    if (!majorSel || majorSel.disabled) return;
    try {
      majorSel.focus();
      if (majorSel.scrollIntoView) majorSel.scrollIntoView({ block: "nearest" });
    } catch (e) { /* ignore */ }
  }

  /* App 传过来的是学院中文名时，按去掉「学院/学部/系」后的名字匹配。 */
  function normCollegeName(raw) {
    return String(raw || "").normalize("NFKC")
      .replace(/[（）()]/g, "")
      .replace(/学院|学部|系/g, "")
      .replace(/\s+/g, "")
      .trim();
  }
  var COLLEGE_NAME_ALIASES = {
    "外国语言文化": "外国语",
    "白求恩口腔医学": "口腔医学"
  };
  function findCollegeByName(raw) {
    var key = normCollegeName(raw);
    if (!key) return null;
    key = COLLEGE_NAME_ALIASES[key] || key;
    var exact = colleges.filter(function (c) { return normCollegeName(c.name) === key; });
    if (exact.length) return exact[0];
    var partial = colleges.filter(function (c) {
      var n = normCollegeName(c.name);
      return n.indexOf(key) >= 0 || key.indexOf(n) >= 0;
    });
    partial.sort(function (a, b) {
      return normCollegeName(b.name).length - normCollegeName(a.name).length;
    });
    return partial[0] || null;
  }

  function entriesOf(code) {
    if (!sid || !sid.entries) return [];
    return sid.entries.filter(function (e) {
      return String(e.code).toLowerCase() === String(code).toLowerCase();
    });
  }

  /* 解析学号 / 邮箱前缀。
   * 纯数字 4 位（如 2124）→ 只取后两位作入学年（2024），学院不猜；
   * 纯数字 ≥6 位 → 学院代码在最前（最长前缀匹配），随后 2 位年份（+班号+序号）；
   * 邮箱前缀（姓名拼音 + 代码 + 年份…）→ 代码必须在字母后面，余下 2 位年份或 6 位完整学号。
   */
  function parseAccount(raw) {
    var s = String(raw || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    if (!s) return null;

    function yearFrom(rest) {
      if (!/^\d{2}/.test(rest)) return null;
      var yy = Number(rest.slice(0, 2));
      if (yy < 10 || yy > 40) return null;
      return "20" + rest.slice(0, 2);
    }

    if (/^\d+$/.test(s)) {
      /* 4 位学号：2124 = 21（学院位）+ 24（2024 级）。学院认不出也不丢年级。 */
      if (s.length === 4) {
        var y4 = yearFrom(s.slice(2));
        return y4 ? { code: null, year: y4, input: s } : null;
      }
      if (!sid || !sid.entries) return null;
      var codes = Array.from(new Set(sid.entries.map(function (e) { return String(e.code).toLowerCase(); })))
        .sort(function (a, b) { return b.length - a.length || a.localeCompare(b); });
      // 学院代码一定在最前面，按最长前缀匹配。
      // 21230102 = 21（计算机）+ 23（2023 级）+ 01 班 + 02 号，绝不能把后面的 23 当学院。
      for (var i = 0; i < codes.length; i++) {
        var c0 = codes[i];
        if (s.indexOf(c0) !== 0) continue;
        var rest0 = s.slice(c0.length);
        if (rest0.length !== 2 && rest0.length !== 6) continue;
        var y0 = yearFrom(rest0);
        if (y0) return { code: c0, year: y0, input: s };
      }
      return null;
    }

    if (!sid || !sid.entries) return null;
    var codes2 = Array.from(new Set(sid.entries.map(function (e) { return String(e.code).toLowerCase(); })))
      .sort(function (a, b) { return b.length - a.length || a.localeCompare(b); });
    // 邮箱前缀：姓名拼音 + 学院代码 + 入学年份（+班号/序号）。
    // 代码必须在字母后面（不能藏在年份/班号数字里），且余下只能是 2 位年份或 6 位完整学号后缀。
    for (var j = 0; j < codes2.length; j++) {
      var code = codes2[j];
      var idx = s.indexOf(code);
      while (idx >= 0) {
        var prev = idx > 0 ? s.charAt(idx - 1) : "";
        var rest = s.slice(idx + code.length);
        var boundary = !prev || /[a-z]/.test(prev);
        if (boundary && (rest.length === 2 || rest.length === 6)) {
          var y = yearFrom(rest);
          if (y) return { code: code, year: y, input: s };
        }
        idx = s.indexOf(code, idx + 1);
      }
    }
    return null;
  }

  function detect() {
    var p = parseAccount(accountInput ? accountInput.value : "");
    if (!p) {
      say("没识别出「院系代码 + 入学年份」。可输入 <b>zhangsw2124</b>（21 + 24）、8 位学号 21240123，" +
        "或 4 位 <b>2124</b>（后两位=2024 级）；也可以在下方「年级」里手选。");
      return;
    }
    applyParsed(p);
  }

  /* 解析结果统一走这里：落年级、认学院、同码时列候选。 */
  function applyParsed(p) {
    /* 年级先落盘：就算学院认不出，4 位/8 位里的年份也已按你的规则生效并记住。 */
    desiredYear = Number(p.year);
    yearAuto = true;
    yearSrc = p.code ? "sid" : "sid4";
    storeYear(desiredYear, true, yearSrc);
    syncYearSel();
    detectedLabel = p.code
      ? "识别到：" + p.code + " · " + desiredYear + " 级"
      : "从 4 位学号后两位识别：" + desiredYear + " 级（学院需手动选）";

    if (!p.code) {
      say(detectedLabel + "<br>学院没认出来（4 位只含年级），请在上方选学院/专业；方案已按 " + desiredYear + " 级匹配。");
      fillMajors();
      return;
    }

    var entries = entriesOf(p.code);
    var head = detectedLabel + " · " + (entries.length
      ? entries.map(function (e) { return e.name; }).join(" / ")
      : "未收录学院");

    if (!entries.length) {
      say(head + "<br>数据库里没有这个学院；请手动选择学院/专业，年级仍按 " + desiredYear + " 级。");
      fillMajors();
      return;
    }
    if (entries.length === 1) {
      chooseCollege(entries[0].code, head);
      return;
    }

    // 同码多院（25 / 81 等）：不替用户写死，列候选让用户点
    var buttons = entries.map(function (e) {
      return "<button type='button' class='dup-btn' data-code='" + e.code +
        "' data-name='" + e.name + "'>" + e.name + "</button>";
    }).join("");
    say(head + "<br>这个代码对应多个学院，请选一个：<div class='dup-row'>" + buttons + "</div>");
    accountResult.querySelectorAll(".dup-btn").forEach(function (b) {
      b.addEventListener("click", function () {
        var code = b.dataset.code;
        var c = byCode[String(code).toLowerCase()];
        if (!c) {
          say(head + "<br><b>" + b.dataset.name + "</b> 目前没有收录方案；可先选另一个，或手动选择。");
          return;
        }
        chooseCollege(code, head + "<br>已选择：" + b.dataset.name);
      });
    });
  }

  if (refreshBtn) {
    refreshBtn.addEventListener("click", async function () {
      refreshBtn.disabled = true;
      say("正在检查方案库版本…");
      try {
        var res = await fetch("data/plans-index.js?ts=" + Date.now(), { cache: "no-store" });
        var text = await res.text();
        var a = text.indexOf("{");
        var b = text.lastIndexOf(";");
        var fresh = JSON.parse(text.slice(a, b));
        var oldCount = (data.meta && data.meta.planCount) || 0;
        var newCount = (fresh.meta && fresh.meta.planCount) || 0;
        if (oldCount === newCount && (data.meta || {}).updated === (fresh.meta || {}).updated) {
          say("方案库已是最新：<b>" + newCount + "</b> 个方案。");
        } else {
          sessionStorage.setItem("GPA_INDEX_REFRESH", JSON.stringify(fresh));
          say("发现新版本（" + newCount + " 个方案），正在刷新…");
          setTimeout(function () { location.href = "index.html?refresh=" + Date.now(); }, 400);
        }
      } catch (e) {
        say("读取方案库失败；file:// 下可能被浏览器拦截，直接刷新页面即可。");
      } finally {
        refreshBtn.disabled = false;
      }
    });
  }

  if (importBtn && importFile) {
    importBtn.addEventListener("click", function () { importFile.click(); });
    importFile.addEventListener("change", function () {
      var file = importFile.files && importFile.files[0];
      if (!file) return;
      var reader = new FileReader();
      reader.onload = function () {
        try {
          var obj = JSON.parse(String(reader.result || ""));
          if (!obj || !obj.courses || !obj.courses.length) throw new Error("no courses");
          var key = "local-" + Date.now();
          localStorage.setItem("jlu-plan-local-" + key, JSON.stringify(obj));
          location.href = "plan.html?local=" + encodeURIComponent(key);
        } catch (e) {
          say("导入失败：这个文件不是本工具导出的培养方案 JSON。");
        }
      };
      reader.readAsText(file, "utf-8");
    });
  }

  if (detectBtn) detectBtn.addEventListener("click", detect);
  if (accountInput) {
    accountInput.addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); detect(); }
    });
  }
  /* 「手动选」只收起识别提示，不再清掉已识别/已选的年级。 */
  if (manualBtn) {
    manualBtn.addEventListener("click", function () {
      if (accountResult) accountResult.hidden = true;
      if (accountInput) accountInput.value = "";
      collegeSel.focus();
      fillMajors();
    });
  }

  /* 年级下拉：手选也持久化（来源=manual，不再标“从学号识别”） */
  if (yearSel) {
    yearSel.addEventListener("change", function () {
      var v = yearSel.value ? Number(yearSel.value) : null;
      setYear(v, false, "manual");
      hint.textContent = describeYear();
    });
  }

  collegeSel.addEventListener("change", fillMajors);
  majorSel.addEventListener("change", showPreview);
  goBtn.addEventListener("click", function () {
    var g = currentGroup();
    var plan = pickPlan(g);
    if (plan) {
      if (desiredYear && plan.year !== desiredYear) storeYear(plan.year, false, "manual");
      window.location.href = plan.route;
    }
  });

  /* App 深链（全部放在 fragment，不进服务器日志）：
   *   #college=55&year=2023           App 已经认出学院
   *   #sid=55230123                  只有学号
   *   #account=zhangcyy5522          只有邮箱前缀
   *   #collegeName=软件学院          学院中文名
   *   #major=软件工程                可选：预选专业
   */
  function readHint(name) {
    var hp = new URLSearchParams((location.hash || "").replace(/^#/, ""));
    var qp = new URLSearchParams(location.search || "");
    var v = hp.get(name);
    if (v === null) v = qp.get(name);
    return v ? String(v).trim() : "";
  }

  function selectMajor(name) {
    var g = groups.find(function (x) { return x.major === name; });
    if (!g) return false;
    majorSel.value = g.major;
    showPreview();
    return true;
  }

  function fromHash() {
    var sidHint = readHint("sid");
    var accountHint = readHint("account");
    var codeHint = readHint("college");
    var nameHint = readHint("collegeName");
    var yearHint = readHint("year");
    var majorHint = readHint("major");
    if (!sidHint && !accountHint && !codeHint && !nameHint && !yearHint) return;

    if (accountInput) accountInput.value = sidHint || accountHint || accountInput.value;

    var sidParsed = sidHint ? parseAccount(sidHint) : null;
    var acctParsed = accountHint ? parseAccount(accountHint) : null;
    function known(p) {
      return !!(p && p.code && byCode[String(p.code).toLowerCase()]);
    }
    // 学号优先，但只有「方案库里认得的代码」才优先，避免学号里的代码没收录时
    // 把还能认的账号也一起放弃。
    var parsed = known(sidParsed) ? sidParsed
               : (known(acctParsed) ? acctParsed
               : (sidParsed || acctParsed));

    /* 年级：显式 year > 学号/账号里的年级。 */
    var y = /^20\d{2}$/.test(yearHint) ? Number(yearHint)
          : (parsed && parsed.year ? Number(parsed.year) : null);
    if (y) {
      desiredYear = y;
      yearAuto = !!(parsed && parsed.year) && !yearHint;
      yearSrc = yearHint ? "link" : (parsed && parsed.code ? "sid" : "sid4");
      storeYear(desiredYear, yearAuto, yearSrc);
      syncYearSel();
    }

    /* 学院：App 已经认出来就直接预填；否则再按学号/账号认一次。 */
    var hinted = null;
    if (codeHint) hinted = byCode[String(codeHint).toLowerCase()] || null;
    if (!hinted && nameHint) hinted = findCollegeByName(nameHint);
    var yearNote = desiredYear ? "，" + desiredYear + " 级" : "";

    if (hinted) {
      chooseCollege(hinted.code, "已按 App 里的设置预填" + yearNote);
    } else if (codeHint || nameHint) {
      say("App 带来的学院（" + (nameHint || codeHint) + "）在方案库里没有找到；请手动选择学院。");
      fillMajors();
    } else if (parsed) {
      applyParsed(parsed);
    } else if (sidHint || accountHint) {
      say("没识别出「院系代码 + 入学年份」。可输入 <b>zhangsw2124</b>（21 + 24）、8 位学号 21240123，" +
        "或 4 位 <b>2124</b>（后两位=2024 级）；也可以在下方「年级」里手选。");
    } else {
      fillMajors();
      say("已按链接里的 " + (desiredYear || "") + " 级预填；请选择学院和专业。");
    }

    if (majorHint) selectMajor(majorHint);
  }

  /* ===== 启动：记忆里有年级就用，没有再试深链识别 ===== */
  var stored = readStoredYear();
  if (stored) {
    desiredYear = stored;
    yearAuto = localStorage.getItem(YEAR_AUTO_KEY) === "1";
    yearSrc = localStorage.getItem(YEAR_SRC_KEY) || (yearAuto ? "sid" : "manual");
    syncYearSel();
  }
  fillMajors();
  fromHash();
})();
