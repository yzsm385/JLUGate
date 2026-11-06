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

  var colleges = data.colleges.slice().sort(function (a, b) {
    return (a.code || "").localeCompare(b.code || "", "zh-CN", { numeric: true });
  });
  var byCode = {};
  colleges.forEach(function (c) { byCode[String(c.code).toLowerCase()] = c; });

  var groups = [];          // 当前学院的专业组（同名专业跨年份合并）
  var desiredYear = null;   // 学号识别出的入学年份，如 2023
  var detectedLabel = "";

  colleges.forEach(function (c) {
    var o = document.createElement("option");
    o.value = c.code;
    o.textContent = (c.code ? c.code + " · " : "") + c.name + "（" + c.majors.length + "）";
    collegeSel.appendChild(o);
  });

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

  function pickPlan(group) {
    if (!group || !group.plans.length) return null;
    if (desiredYear) {
      var older = group.plans.filter(function (p) { return p.year <= desiredYear; });
      if (older.length) return older[0]; // 已按年份降序，取最靠近的 ≤ 入学年
      return null;
    }
    return group.plans[0]; // 没识别年级：取最新
  }

  function yearText(plan) {
    if (!desiredYear) return "未识别年级，默认 " + plan.year + " 级方案";
    if (plan.year === desiredYear) return desiredYear + " 级方案";
    return desiredYear + " 级没有方案，已回滚到 " + plan.year + " 级";
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
    hint.textContent = c.name + "：共 " + groups.length + " 个专业；" +
      (desiredYear ? "按 " + desiredYear + " 级回滚查找方案。" : "未识别年级，默认最新方案。");
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
        desiredYear + " 级及更早方案</span></div>" +
        "<div class='preview-note'>数据库里这个专业只有 " + years.join(" / ") +
        " 级；按“向更早年份回滚”的规则，不能拿更晚的方案顶替。请补对应年份的培养方案。</div>";
      return;
    }
    goBtn.disabled = false;
    preview.hidden = false;
    var special = plan.route.indexOf("software.html") === 0 || plan.route.indexOf("computer.html") === 0;
    preview.innerHTML =
      "<div class='preview-main'><b>" + g.major + " · " + plan.year + " 级</b>" +
      "<span>" + (special ? "专门版" : plan.year + " 主修通用目录") + "</span></div>" +
      "<div class='preview-meta'>" + plan.courses + " 门课程 · 计划 " + plan.credits +
      " 学分 · " + yearText(plan) + "</div>" +
      "<div class='preview-note'>" + (special
        ? "进入后可切换 2022 参考 / 2023-24 / 2025 推算 / 2026 真实目录，并选择英语 A/B/预备级或日德法俄西。"
        : "通用页列出该方案全部课程，默认不勾选；2026 推免细则未发布，请按实际修读/计入勾选。") + "</div>";
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
    return true;
  }

  function entriesOf(code) {
    if (!sid || !sid.entries) return [];
    return sid.entries.filter(function (e) {
      return String(e.code).toLowerCase() === String(code).toLowerCase();
    });
  }

  function parseAccount(raw) {
    var s = String(raw || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    if (!s || !sid || !sid.entries) return null;
    var codes = Array.from(new Set(sid.entries.map(function (e) { return String(e.code).toLowerCase(); })))
      .sort(function (a, b) { return b.length - a.length || a.localeCompare(b); });
    for (var i = 0; i < codes.length; i++) {
      var code = codes[i];
      var idx = s.lastIndexOf(code);
      if (idx < 0) continue;
      var rest = s.slice(idx + code.length);
      if (!/^\d{2}/.test(rest)) continue;
      var yy = Number(rest.slice(0, 2));
      if (yy < 10 || yy > 40) continue;
      return { code: code, year: "20" + rest.slice(0, 2), input: s };
    }
    return null;
  }

  function detect() {
    var p = parseAccount(accountInput ? accountInput.value : "");
    if (!p) {
      say("没识别出「院系代码 + 入学年份」。可输入 <b>zhangsw2123</b>（21 + 23）或 8 位学号；也可以直接手动选学院。");
      return;
    }
    desiredYear = Number(p.year);
    detectedLabel = "识别到：" + p.code + " · " + p.year + " 级";
    var entries = entriesOf(p.code);
    var head = detectedLabel + " · " + (entries.length
      ? entries.map(function (e) { return e.name; }).join(" / ")
      : "未收录学院");

    if (!entries.length) {
      say(head + "<br>数据库里没有这个学院；请手动选择。");
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
  if (manualBtn) {
    manualBtn.addEventListener("click", function () {
      desiredYear = null;
      detectedLabel = "";
      if (accountResult) accountResult.hidden = true;
      if (accountInput) accountInput.value = "";
      collegeSel.focus();
      fillMajors();
    });
  }

  collegeSel.addEventListener("change", fillMajors);
  majorSel.addEventListener("change", showPreview);
  goBtn.addEventListener("click", function () {
    var g = currentGroup();
    var plan = pickPlan(g);
    if (plan) window.location.href = plan.route;
  });

  // App 深链：https://yzsm385.github.io/JLUGate/#account=zhangsw2123
  // 账号只放 fragment，不会出现在服务器日志里。
  function fromHash() {
    var raw = (location.hash || "").replace(/^#/, "");
    if (!raw) return;
    var hp = new URLSearchParams(raw);
    var qp = new URLSearchParams(location.search || "");
    var a = hp.get("account") || qp.get("account");
    if (a && accountInput) {
      accountInput.value = a;
      detect();
    }
  }
  fromHash();
})();
