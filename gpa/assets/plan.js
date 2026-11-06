(function () {
  var SEM = { 0: "未标注", 1: "大一上", 2: "大一下", 3: "大二上", 4: "大二下", 5: "大三上", 6: "大三下", 7: "大四上", 8: "大四下" };
  var GPA_OPTIONS = [
    ["4.0", "4.0 · 90–100"], ["3.7", "3.7 · 87–89.9"], ["3.3", "3.3 · 84–86.9"],
    ["3.0", "3.0 · 80–83.9"], ["2.7", "2.7 · 77–79.9"], ["2.3", "2.3 · 74–76.9"],
    ["2.0", "2.0 · 70–73.9"], ["1.7", "1.7 · 67–69.9"], ["1.3", "1.3 · 64–66.9"],
    ["1.0", "1.0 · 60–63.9"], ["0.0", "0.0 · 60 以下"]
  ];
  var params = new URLSearchParams(window.location.search);
  var planId = (params.get("plan") || "").trim();
  var version = (params.get("v") || "").trim();
  var year = (params.get("y") || "").trim();
  var localKey = (params.get("local") || "").trim();
  var title = document.getElementById("planTitle");
  var meta = document.getElementById("planMeta");
  var list = document.getElementById("planList");
  var status = document.getElementById("planStatus");
  var search = document.getElementById("planSearch");
  var clearBtn = document.getElementById("clearPlan");
  var stateKey = "jlu-plan-v1-" + (localKey ? "local-" + localKey : planId);
  var state = { checked: {}, gpa: {} };
  var onlyFirst3Input = document.getElementById("onlyFirst3");
  var onlyFirst3 = localStorage.getItem("jlu-plan-first3") !== "0";
  var targetInput = document.getElementById("targetGpa");
  var target = Number(localStorage.getItem("jlu-plan-target")) || 3.46;
  var plan = null;

  function fail(msg) {
    if (title) title.textContent = "没有找到这个专业的方案";
    if (meta) meta.textContent = msg;
    if (list) list.innerHTML = "<p class='fine'>请回到首页，重新选择学院和专业。</p>";
  }

  if (!localKey && (!planId || !/^[0-9a-f]{16,40}$/i.test(planId))) {
    fail("地址里缺少 plan 参数。");
    return;
  }

  try {
    var saved = JSON.parse(localStorage.getItem(stateKey) || "{}");
    state.checked = saved.checked || {};
    state.gpa = saved.gpa || {};
  } catch (e) { /* ignore */ }

  function save() {
    try { localStorage.setItem(stateKey, JSON.stringify(state)); } catch (e) { /* ignore */ }
  }

  function num(x) { return Number(x) || 0; }

  function calc() {
    var sel = 0, selCr = 0, graded = 0, gradedCr = 0, weighted = 0, remCr = 0, remCount = 0;
    plan.courses.forEach(function (c) {
      if (!state.checked[c.key]) return;
      if (onlyFirst3 && c.sem >= 7) return;
      sel++;
      selCr += num(c.credit);
      var g = state.gpa[c.key];
      if (g !== undefined && g !== "") {
        graded++;
        gradedCr += num(c.credit);
        weighted += Number(g) * num(c.credit);
      } else {
        remCount++;
        remCr += num(c.credit);
      }
    });
    var need = remCr > 0 ? (target * selCr - weighted) / remCr : null;
    return {
      sel: sel, selCr: selCr, graded: graded, gradedCr: gradedCr,
      remCr: remCr, remCount: remCount,
      gpa: gradedCr > 0 ? weighted / gradedCr : null,
      need: need
    };
  }

  function updateStats() {
    var r = calc();
    document.getElementById("selCredits").textContent = r.selCr.toFixed(1);
    document.getElementById("selSub").textContent = r.sel + " 门课程 · 已录 " + r.graded + " 门 / 待录 " + r.remCount + " 门";
    document.getElementById("planGpa").textContent = r.gpa == null ? "—" : r.gpa.toFixed(6);
    document.getElementById("gpaSub").textContent = r.gradedCr > 0
      ? r.gradedCr.toFixed(1) + " 学分计入 GPA"
      : "录入绩点后显示";
    if (r.sel === 0) {
      document.getElementById("needGpa").textContent = "—";
      document.getElementById("needSub").textContent = "先勾选课程";
    } else if (r.remCr <= 0) {
      document.getElementById("needGpa").textContent = "—";
      document.getElementById("needSub").textContent = "已全部录入；最终 " +
        (r.gpa == null ? "—" : r.gpa.toFixed(6)) + (r.gpa == null ? "" : (r.gpa >= target ? "，达到目标" : "，未达目标"));
    } else {
      document.getElementById("needGpa").textContent = r.need == null ? "—" : Math.max(0, r.need).toFixed(3);
      document.getElementById("needSub").textContent = "剩余 " + r.remCr.toFixed(1) + " 学分" +
        (r.need > 4.0 ? " · 目标偏高（需 >4.0）" : (r.need < 0 ? " · 已超过目标" : ""));
    }
  }

  function makeRow(c) {
    var row = document.createElement("div");
    row.className = "plan-row";
    row.dataset.text = (c.name + " " + (c.code || "") + " " + (c.note || "")).toLowerCase();

    var main = document.createElement("label");
    main.className = "plan-check";
    var cb = document.createElement("input");
    cb.type = "checkbox";
    cb.checked = !!state.checked[c.key];
    cb.dataset.key = c.key;
    var span = document.createElement("span");
    span.className = "plan-name";
    span.innerHTML = "<b>" + c.name + "</b><em>" + (c.code || "") + " · " + num(c.credit) +
      " 学分 · " + (c.type || "") + (c.note ? " · " + c.note : "") + "</em>";
    main.appendChild(cb);
    main.appendChild(span);
    row.appendChild(main);

    var sel = document.createElement("select");
    sel.className = "plan-gpa";
    sel.dataset.key = c.key;
    sel.disabled = !state.checked[c.key];
    var opt0 = document.createElement("option");
    opt0.value = "";
    opt0.textContent = "— 选绩点";
    sel.appendChild(opt0);
    GPA_OPTIONS.forEach(function (o) {
      var op = document.createElement("option");
      op.value = o[0];
      op.textContent = o[1];
      sel.appendChild(op);
    });
    sel.value = state.gpa[c.key] || "";
    row.appendChild(sel);
    return row;
  }

  function renderList() {
    list.innerHTML = "";
    var bySem = {};
    plan.courses.forEach(function (c) {
      (bySem[c.sem] = bySem[c.sem] || []).push(c);
    });
    Object.keys(bySem).map(Number).sort(function (a, b) {
      if (a === 0) return 1;
      if (b === 0) return -1;
      return a - b;
    }).forEach(function (sem) {
      var sec = document.createElement("section");
      sec.className = "plan-sem";
      sec.dataset.sem = String(sem);
      var h = document.createElement("h3");
      h.textContent = sem === 0 ? "未标注学期（英语分级 / 四史等）" : "第 " + sem + " 学期 · " + (SEM[sem] || "其他");
      sec.appendChild(h);
      var box = document.createElement("div");
      box.className = "plan-rows";
      bySem[sem].forEach(function (c) { box.appendChild(makeRow(c)); });
      sec.appendChild(box);
      list.appendChild(sec);
    });
    applySearch();
  }

  function applySearch() {
    var q = (search.value || "").trim().toLowerCase();
    document.querySelectorAll(".plan-sem").forEach(function (sec) {
      var shown = 0;
      sec.querySelectorAll(".plan-row").forEach(function (row) {
        var hit = !q || row.dataset.text.indexOf(q) >= 0;
        row.hidden = !hit;
        if (hit) shown++;
      });
      sec.hidden = shown === 0 || (onlyFirst3 && Number(sec.dataset.sem) >= 7);
    });
  }

  list.addEventListener("change", function (e) {
    var el = e.target;
    if (el.matches("input[type=checkbox]")) {
      var key = el.dataset.key;
      if (el.checked) state.checked[key] = true;
      else { delete state.checked[key]; delete state.gpa[key]; }
      var sel = list.querySelector("select.plan-gpa[data-key='" + key + "']");
      if (sel) { sel.disabled = !el.checked; if (!el.checked) sel.value = ""; }
      save();
      updateStats();
      return;
    }
    if (el.matches("select.plan-gpa")) {
      var k = el.dataset.key;
      if (el.value) state.gpa[k] = el.value; else delete state.gpa[k];
      save();
      updateStats();
    }
  });

  if (targetInput) {
    targetInput.value = target.toFixed(2);
    targetInput.addEventListener("input", function () {
      var v = Number(targetInput.value);
      if (!isFinite(v)) return;
      target = Math.max(0, Math.min(4, v));
      try { localStorage.setItem("jlu-plan-target", String(target)); } catch (e) { /* ignore */ }
      updateStats();
    });
  }

  var selectRequired = document.getElementById("selectRequired");
  if (selectRequired) selectRequired.addEventListener("click", function () {
    plan.courses.forEach(function (c) {
      if (c.type === "必修" && (!onlyFirst3 || c.sem < 7)) state.checked[c.key] = true;
    });
    save(); renderList(); updateStats();
    status.textContent = "已选必修（" + (onlyFirst3 ? "不含大四" : "含大四") + "）；可能含英语/方向分流，请按实际取消。";
  });

  if (onlyFirst3Input) {
    onlyFirst3Input.checked = onlyFirst3;
    onlyFirst3Input.addEventListener("change", function () {
      onlyFirst3 = this.checked;
      try { localStorage.setItem("jlu-plan-first3", onlyFirst3 ? "1" : "0"); } catch (e) { /* ignore */ }
      applySearch();
      updateStats();
    });
  }

  search.addEventListener("input", applySearch);
  clearBtn.addEventListener("click", function () {
    state = { checked: {}, gpa: {} };
    save();
    renderList();
    updateStats();
    status.textContent = "已清空勾选和成绩。";
  });

  function render() {
    var m = plan.meta || {};
    document.title = m.planName + " · GPA";
    title.textContent = m.planName;
    meta.textContent = (m.college ? m.college + " · " : "") + (m.major || "") +
      " · " + (m.totalPlanCredits ? "计划 " + m.totalPlanCredits + " 学分" : "");
    var ym = String(m.planName || "").match(/(20\d{2})级/);
    var yText = ym ? ym[1] : "";
    document.getElementById("badgeCollege").textContent = m.college || "—";
    document.getElementById("badgeYear").textContent = yText ? yText + " 主修目录" : "主修目录";
    document.getElementById("badgeCredits").textContent = "计划 " + (m.totalPlanCredits || "—") + " 学分";
    var fine = document.getElementById("planFine");
    if (fine) fine.textContent = (yText || "当前") + " 推免细则以学院当年通知为准：这里只列培养方案全部课程，默认不勾选。勾选你实际修读/计入的课程，再录绩点；每门都可取消。勾选与成绩只保存在本机。";
    renderList();
    updateStats();
  }

  if (localKey) {
    try {
      plan = JSON.parse(localStorage.getItem("jlu-plan-local-" + localKey) || "null");
    } catch (e) { plan = null; }
    if (!plan || !plan.courses) { fail("本地导入的方案不存在或已损坏。"); return; }
    render();
  } else {
    var s = document.createElement("script");
    s.src = "data/plans/" + (year && /^20\d{2}$/.test(year) ? year + "/" : "") + planId + ".js" +
      (version ? "?v=" + encodeURIComponent(version) : "");
    s.onload = function () {
      plan = window.GPA_PLAN;
      if (!plan || !plan.courses) { fail("方案数据为空。"); return; }
      render();
    };
    s.onerror = function () { fail("读取 data/plans/" + planId + ".js 失败。"); };
    document.head.appendChild(s);
  }

  var downloadBtn = document.getElementById("downloadPlan");
  if (downloadBtn) downloadBtn.addEventListener("click", function () {
    if (!plan) return;
    var blob = new Blob([JSON.stringify(plan, null, 2)], { type: "application/json" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = (plan.meta && plan.meta.planName ? plan.meta.planName : "培养方案") + ".json";
    document.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
    status.textContent = "已下载本专业方案；可回到首页“导入方案”离线打开。";
  });
})();
