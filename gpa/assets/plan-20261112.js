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
  var showExcludedInput = document.getElementById("showExcluded");
  var showExcluded = localStorage.getItem("jlu-plan-show-excluded") === "1";
  var targetInput = document.getElementById("targetGpa");
  var target = Number(localStorage.getItem("jlu-plan-target")) || 3.46;
  var plan = null;
  var planByKey = {};

  /* ===== 学院口径：来自 gpa/data/college-rules.js（各学院推免细则调研） ===== */
  var rule = null;
  var hasRule = false;

  function fail(msg) {
    if (title) title.textContent = "没有找到这个专业的方案";
    if (meta) meta.textContent = msg;
    if (list) list.innerHTML = "<p class='fine'>请回到首页，重新选择学院和专业。</p>";
  }

  if (!localKey && (!planId || !/^[0-9a-f]{16,40}$/i.test(planId))) {
    fail("地址里缺少 plan 参数。");
    return;
  }

  var hasSaved = false;
  try {
    var rawSaved = localStorage.getItem(stateKey);
    hasSaved = rawSaved !== null;
    var saved = JSON.parse(rawSaved || "{}");
    state.checked = saved.checked || {};
    state.gpa = saved.gpa || {};
  } catch (e) { /* ignore */ }

  function save() {
    try { localStorage.setItem(stateKey, JSON.stringify(state)); } catch (e) { /* ignore */ }
  }

  function defaultSelect() {
    if (hasSaved) return;
    plan.courses.forEach(function (c) {
      if (isForeign(c) || isHistory(c)) return;
      if (hardExcluded(c) || unsureExcluded(c)) return;
      if (!onlyFirst3 || c.sem < 7) state.checked[c.key] = true;
    });
    save();
  }

  function num(x) { return Number(x) || 0; }

  function isForeign(c) {
    /* 公共外语课：普通外语课名（大学英语/综合英语/学术英语…）或分级备注（A/B/C级班、预备级、免修级）；
       专业外语（专业英语/商务英语/科技英语/二外/方向模块）是学院专业课，不算公共外语 */
    var n = (c.name || "").trim();
    var t = (c.name || "") + " " + (c.note || "");
    if (/(专业英语|商务英语|科技英语|医学英语|法律英语|国别区域|二外|外语实践组|文献导读组)/.test(t)) return false;
    if (/(大学英语|英语A|英语B|综合英语|学科英语|英语听说|英语视听说|英语写作|学术英语|通用学术英语|英语经典|英语预备|大学日语|大学德语|大学法语|大学俄语|大学西班牙)/.test(n)) return true;
    if (/(B级班|C级班|预备级|免修级|英语A级|英语B级|俄语组|日语组|德语组|法语组|韩语组)/.test((c.note || ""))) return true;
    return false;
  }

  function isHistory(c) {
    return /四史/.test((c.name || "") + " " + (c.note || ""));
  }

  function langOf(c) {
    var t = (c.name || "") + " " + (c.note || "");
    if (/朝鲜语/.test(t)) return "朝鲜语";
    if (/日语/.test(t)) return "日语";
    if (/德语/.test(t)) return "德语";
    if (/法语/.test(t)) return "法语";
    if (/俄语/.test(t)) return "俄语";
    if (/西班牙/.test(t)) return "西班牙语";
    return "英语";
  }

  /* ===== 推免科目判定（2026-11 全校调研结论） =====
     确定不计入 → 直接隐藏（「显示不计入课程」开关可看）：
       体育、军事教育（军事理论/军训）、选修/限选（体育学院按逐门公示清单计入，除外）。
     疑似不计入/按届不同 → 每学期底部折叠组：
       新生研讨/学科导论（部分学院点名不计）、sem=0 的同名分流（5选1/7选1 等）。
     英语与四史走页首单独选择面板。 */
  function isPE(c) {
    var n = (c.name || "").trim();
    return /^体育[ⅠⅡⅢⅣⅤ1-9一二三四五]/.test(n) || n === "体育" || n === "体育课";
  }
  function isMilitary(c) {
    var n = (c.name || "").trim();
    return /^军事(理论|训练|教育|技能)$/.test(n);
  }
  function isElective(c) {
    return (c.type || "") === "选修" || (c.type || "") === "限选";
  }
  function isPECollege() {
    return !!(rule && /体育学院/.test(rule.name || ""));
  }
  function hardExcluded(c) {
    if (isMilitary(c)) return true;
    if (isPE(c)) return true;
    if (isElective(c) && !isPECollege()) return true;
    return false;
  }
  function hardReason(c) {
    if (isMilitary(c)) return "军事教育 · 各院细则均不计入";
    if (isPE(c)) return "体育 · 各院细则均不计入";
    if (isElective(c)) return isPECollege() ? "体育学院 · 按公示清单计入" : "选修/限选 · 多数学院不计入";
    return "";
  }
  function unsureExcluded(c) {
    if (isForeign(c) || isHistory(c)) return false;
    if (c.sem === 0 && /拓展（5选1|拓展（7选1|B级班|C级班|预备级|免修级|A级综合|B级综合|A级学科|B级学科|A级拓展|B级拓展|俄语组|日语组|德语组|法语组|韩语组/.test((c.name || "") + " " + (c.note || ""))) return true;
    var n = (c.name || "").trim();
    if (!isElective(c) && /(新生研讨课|新生研讨与学科导论|学科导论课?$|学科导论$|学科前沿导论)/.test(n)) return true;
    return false;
  }
  function unsureReason(c) {
    var n = (c.name || "").trim();
    if (/新生研讨|学科导论|学科前沿导论/.test(n)) return "新生研讨/导论 · 部分学院点名不计入";
    return "同名分流 · 仅一门会计入";
  }
  function isExcluded(c) { return hardExcluded(c) || unsureExcluded(c); }

  /* ===== 计算 ===== */
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

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (ch) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch];
    });
  }

  function fmtGpa(v) {
    if (v == null || v === "" || !isFinite(Number(v))) return "—";
    var n = Number(v);
    return (Math.round(n * 1e6) / 1e6).toFixed(6).replace(/0{2,}$/, "").replace(/\.$/, ".0");
  }

  /* ===== 学院口径 + 推免线面板 ===== */
  function renderRulesPanel() {
    if (!rule) return;
    var sec = document.createElement("section");
    sec.className = "choice-panel rules-panel";
    var h = document.createElement("h3");
    h.appendChild(document.createTextNode(rule.name + " · 推免口径与历年线 "));
    var badge = document.createElement("span");
    badge.className = "rules-badge" + (rule.confidence === "high" ? " ok" : "");
    badge.textContent = hasRule ? "已核对学院细则" : "未找到学院细则";
    h.appendChild(badge);
    sec.appendChild(h);

    if (rule.summary) {
      var p = document.createElement("p");
      p.className = "choice-hint";
      p.innerHTML = "<b>计分口径：</b>" + esc(rule.summary);
      sec.appendChild(p);
    }

    if (rule.lines && rule.lines.length) {
      var tbl = document.createElement("table");
      tbl.className = "rules-lines";
      var cap = document.createElement("caption");
      cap.textContent = "历年推免线（学业 GPA，不含加分）";
      tbl.appendChild(cap);
      var thead = document.createElement("thead");
      thead.innerHTML = "<tr><th>届</th><th>选拔规则</th><th>选拔线</th><th>最后一名</th><th>名额/年级</th></tr>";
      tbl.appendChild(thead);
      var tb = document.createElement("tbody");
      rule.lines.forEach(function (L) {
        var tr = document.createElement("tr");
        var cells = [
          esc(L.cohort || "") + (L.major ? " · " + esc(L.major) : ""),
          esc(L.selectionRule || "—"),
          fmtGpa(L.selectionGpa),
          fmtGpa(L.lastAdmittedGpa),
          (L.quota != null ? esc(String(L.quota)) : "—") + "/" + (L.cohortSize != null ? esc(String(L.cohortSize)) : "—") + (L.quotaRatio ? " (" + esc(L.quotaRatio) + ")" : "")
        ];
        cells.forEach(function (t) {
          var td = document.createElement("td");
          td.innerHTML = t;
          tr.appendChild(td);
        });
        if (L.source) tr.title = L.source;
        tb.appendChild(tr);
      });
      tbl.appendChild(tb);
      sec.appendChild(tbl);
    } else {
      var no = document.createElement("p");
      no.className = "choice-hint";
      no.textContent = "本院历年推免线：公示材料里没查到具体分数（可展开下方「学院通知」核对原文）。";
      sec.appendChild(no);
    }

    if (rule.notices && rule.notices.length) {
      var d = document.createElement("details");
      d.className = "rules-notices";
      var s = document.createElement("summary");
      s.textContent = "学院通知（细则 / 排名公示原文链接）";
      d.appendChild(s);
      var ul = document.createElement("ul");
      rule.notices.forEach(function (n) {
        var li = document.createElement("li");
        var a = document.createElement("a");
        a.href = n.u;
        a.target = "_blank";
        a.rel = "noopener";
        a.textContent = (n.p || "") + " " + (n.t || "");
        li.appendChild(a);
        ul.appendChild(li);
      });
      d.appendChild(ul);
      sec.appendChild(d);
    }
    list.appendChild(sec);
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
    var hard = hardExcluded(c);
    var unsure = !hard && unsureExcluded(c);
    if (hard) row.classList.add("row-hard");
    if (unsure) row.classList.add("row-unsure");
    if ((hard || unsure) && state.checked[c.key]) row.classList.add("manual");
    row.dataset.text = (c.name + " " + (c.code || "") + " " + (c.note || "")).toLowerCase();

    var main = document.createElement("label");
    main.className = "plan-check";
    var cb = document.createElement("input");
    cb.type = "checkbox";
    cb.checked = !!state.checked[c.key];
    cb.dataset.key = c.key;
    var span = document.createElement("span");
    span.className = "plan-name";
    var reason = hard ? hardReason(c) : (unsure ? unsureReason(c) : "");
    span.innerHTML = "<b>" + esc(c.name) + "</b><em>" + esc(c.code || "") + " · " + num(c.credit) +
      " 学分 · " + esc(c.type || "") + (c.note ? " · " + esc(c.note) : "") +
      (reason ? "<i class='ex-reason'>" + esc(reason) + "</i>" : "") + "</em>";
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

  function renderChoicePanels() {
    var foreign = plan.courses.filter(isForeign);
    var history = plan.courses.filter(isHistory);

    if (foreign.length) {
      var sec = document.createElement("section");
      sec.className = "choice-panel";
      var h = document.createElement("h3");
      h.textContent = "外语（单独选择）";
      sec.appendChild(h);
      var hint = document.createElement("p");
      hint.className = "choice-hint";
      hint.textContent = "先选语种，再展开对应课程；外语默认不勾选。各学院计入的英语级别不同（多数只计 Ⅱ/Ⅲ/Ⅳ 或 Ⅲ/Ⅳ，以本院细则为准）。";
      sec.appendChild(hint);

      var langs = [];
      foreign.forEach(function (c) {
        var l = langOf(c);
        if (langs.indexOf(l) < 0) langs.push(l);
      });
      var selected = "";
      foreign.forEach(function (c) { if (state.checked[c.key] && !selected) selected = langOf(c); });

      var sel = document.createElement("select");
      sel.id = "foreignLang";
      sel.className = "choice-select";
      var o0 = document.createElement("option");
      o0.value = ""; o0.textContent = "请选择语种"; sel.appendChild(o0);
      langs.forEach(function (l) {
        var o = document.createElement("option"); o.value = l; o.textContent = l; sel.appendChild(o);
      });
      sel.value = selected;
      sec.appendChild(sel);

      var groups = {};
      foreign.forEach(function (c) {
        var l = langOf(c);
        if (!groups[l]) {
          groups[l] = document.createElement("div");
          groups[l].className = "lang-group";
          groups[l].dataset.lang = l;
          groups[l].hidden = l !== selected;
          sec.appendChild(groups[l]);
        }
        groups[l].appendChild(makeRow(c));
      });
      list.appendChild(sec);
    }

    if (history.length) {
      var hs = document.createElement("section");
      hs.className = "choice-panel";
      var hh = document.createElement("h3");
      hh.textContent = "四史（4 选 1，单独选择）";
      hs.appendChild(hh);
      var hp = document.createElement("p");
      hp.className = "choice-hint";
      hp.textContent = "四史属通识/限选，多数学院不计入推免学业成绩，默认不勾选；请只选你实际修读的一门。";
      hs.appendChild(hp);
      var hsel = document.createElement("select");
      hsel.id = "historyPick";
      hsel.className = "choice-select";
      var ho0 = document.createElement("option");
      ho0.value = ""; ho0.textContent = "不选 / 请选择"; hsel.appendChild(ho0);
      var current = "";
      history.forEach(function (c) {
        var o = document.createElement("option");
        o.value = c.key;
        o.textContent = c.name + " · " + num(c.credit) + " 学分" + (c.note ? " · " + c.note : "");
        hsel.appendChild(o);
        if (state.checked[c.key]) current = c.key;
      });
      hsel.value = current;
      hs.appendChild(hsel);
      list.appendChild(hs);
    }
  }

  function creditOfGroup(box) {
    var total = 0;
    box.querySelectorAll(".plan-check input").forEach(function (cb) {
      var c = planByKey[cb.dataset.key];
      if (c) total += num(c.credit);
    });
    return total.toFixed(1);
  }

  function renderList() {
    list.innerHTML = "";
    renderRulesPanel();
    renderChoicePanels();
    var bySem = {};
    plan.courses.forEach(function (c) {
      if (isForeign(c) || isHistory(c)) return;
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
      h.textContent = sem === 0 ? "未标注学期" : "第 " + sem + " 学期 · " + (SEM[sem] || "其他");
      sec.appendChild(h);

      var box = document.createElement("div");
      box.className = "plan-rows";
      var unsureBox = null;
      bySem[sem].forEach(function (c) {
        if (unsureExcluded(c)) {
          if (!unsureBox) {
            unsureBox = document.createElement("details");
            unsureBox.className = "ex-group";
            var s = document.createElement("summary");
            s.innerHTML = "<b>疑似不计入 / 按届不同（默认折叠）</b><span></span>";
            unsureBox.appendChild(s);
            var hint = document.createElement("p");
            hint.className = "ex-hint";
            hint.textContent = "这些课程是否计入因学院、年级而异（或同组多选一）；确认计入的再展开勾选。";
            unsureBox.appendChild(hint);
          }
          unsureBox.appendChild(makeRow(c));
        } else if (!hardExcluded(c)) {
          box.appendChild(makeRow(c));
        }
      });

      if (box.children.length || unsureBox) {
        if (box.children.length) sec.appendChild(box);
        if (unsureBox) {
          var lbl = unsureBox.querySelector("summary span");
          if (lbl) lbl.textContent = unsureBox.querySelectorAll(".plan-row").length + " 门 · " + creditOfGroup(unsureBox) + " 学分";
          sec.appendChild(unsureBox);
        }
        list.appendChild(sec);
      }
    });
    applySearch();
  }

  function applySearch() {
    var q = (search.value || "").trim().toLowerCase();
    document.querySelectorAll(".plan-sem").forEach(function (sec) {
      var shown = 0;
      var unsureBox = sec.querySelector(".ex-group");
      var unsureShown = 0;
      sec.querySelectorAll(".plan-row").forEach(function (row) {
        var hit = !q || row.dataset.text.indexOf(q) >= 0;
        row.hidden = !hit;
        if (hit) {
          shown++;
          if (unsureBox && unsureBox.contains(row)) unsureShown++;
        }
      });
      if (unsureBox) {
        if (q) unsureBox.open = unsureShown > 0 || unsureBox.open;
        unsureBox.hidden = q ? unsureShown === 0 : false;
      }
      sec.hidden = shown === 0 || (onlyFirst3 && Number(sec.dataset.sem) >= 7);
    });
  }

  list.addEventListener("change", function (e) {
    var el = e.target;
    if (el.id === "foreignLang") {
      var lang = el.value;
      document.querySelectorAll(".lang-group").forEach(function (g) {
        g.hidden = g.dataset.lang !== lang;
      });
      return;
    }
    if (el.id === "historyPick") {
      plan.courses.forEach(function (c) {
        if (isHistory(c)) delete state.checked[c.key];
      });
      if (el.value) state.checked[el.value] = true;
      save();
      updateStats();
      return;
    }
    if (el.matches("input[type=checkbox]")) {
      var key = el.dataset.key;
      if (el.checked) state.checked[key] = true;
      else { delete state.checked[key]; delete state.gpa[key]; }
      var sel = list.querySelector("select.plan-gpa[data-key='" + key + "']");
      if (sel) { sel.disabled = !el.checked; if (!el.checked) sel.value = ""; }
      var row = el.closest(".plan-row");
      if (row) row.classList.toggle("manual", el.checked && (row.classList.contains("row-hard") || row.classList.contains("row-unsure")));
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
      if (c.type === "必修" && !isForeign(c) && !isHistory(c) && !isExcluded(c) && (!onlyFirst3 || c.sem < 7)) state.checked[c.key] = true;
    });
    save(); renderList(); updateStats();
    status.textContent = "已按学院口径选必修（体育/军事/选修已排除" + (onlyFirst3 ? "，不含大四" : "") + "）。同名分流课程在「疑似不计入」折叠组里，需要再展开勾选。";
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

  if (showExcludedInput) {
    showExcludedInput.checked = showExcluded;
    showExcludedInput.addEventListener("change", function () {
      showExcluded = this.checked;
      try { localStorage.setItem("jlu-plan-show-excluded", showExcluded ? "1" : "0"); } catch (e) { /* ignore */ }
      document.body.classList.toggle("show-excluded", showExcluded);
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
    if (fine) fine.textContent = (yText || "当前") + " 级默认按各学院推免细则勾选：体育、军事教育、选修/限选等确定不计入的课程已隐藏（勾「显示不计入课程」可看）；疑似按届不同的课程折叠在每学期底部。外语与四史在页首单独选择。勾选与成绩只保存在本机。";
    renderList();
    updateStats();
  }

  function loadPlan(p) {
    plan = p;
    if (!plan || !plan.courses) { fail("方案数据为空。"); return; }
    planByKey = {};
    plan.courses.forEach(function (c) { planByKey[c.key] = c; });
    rule = (window.GPA_COLLEGE_RULES && window.GPA_COLLEGE_RULES.rules || {})[String((plan.meta && plan.meta.collegeCode) || "")] || null;
    hasRule = !!(rule && (rule.status === "ok" || rule.status === "partial"));
    defaultSelect();
    render();
  }

  if (localKey) {
    try {
      loadPlan(JSON.parse(localStorage.getItem("jlu-plan-local-" + localKey) || "null"));
    } catch (e) { loadPlan(null); }
    if (!plan) { fail("本地导入的方案不存在或已损坏。"); return; }
  } else {
    var s = document.createElement("script");
    s.src = "data/plans/" + (year && /^20\d{2}$/.test(year) ? year + "/" : "") + planId + ".js" +
      (version ? "?v=" + encodeURIComponent(version) : "");
    s.onload = function () { loadPlan(window.GPA_PLAN); };
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

  document.body.classList.toggle("show-excluded", showExcluded);
})();
