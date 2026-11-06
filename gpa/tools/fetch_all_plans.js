/* JLU 全校培养方案批量抓取（在已登录的 iedu 页面 Console 里运行）
 *
 * 用法：
 * 1. 浏览器登录 https://iedu.jlu.edu.cn/jwapp/sys/qxfacx/*default/index.do
 * 2. F12 → Console，粘贴本文件全部代码，回车
 * 3. 等它下载 JLU_培养方案_2026主修_184.json
 * 4. 把 json 放到 GPA 文件夹，告诉文件名
 *
 * 只读取你当前浏览器会话，不需要账号密码；文件只保存在本机。
 * 184 个方案 × 3 个请求，约 2–4 分钟；控制台会打印进度。
 */
(async () => {
  const BASE = 'https://iedu.jlu.edu.cn';
  const LIST = BASE + '/jwapp/sys/qxfacx/modules/pyfacxepg/qxpyfacxzl.do';
  const HEADERS = { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' };

  // 你要哪一级、哪种类型；不确定就都保留 null
  const YEAR = '2026级';   // 例如 '2026级'；null = 全部年级
  const TYPE = '主修';     // 例如 '主修'；null = 全部类型

  const sleep = ms => new Promise(r => setTimeout(r, ms));

  async function post(url, body) {
    const resp = await fetch(url, {
      method: 'POST',
      headers: HEADERS,
      body,
      credentials: 'include'
    });
    if (!resp.ok) throw new Error(resp.status + ' ' + url);
    const text = await resp.text();
    try { return JSON.parse(text); }
    catch (e) { throw new Error('返回不是 JSON: ' + text.slice(0, 160)); }
  }

  // 与页面相同的筛选：已发布方案（FAZTDM=99）
  const querySetting = encodeURIComponent(JSON.stringify([
    { name: 'FAZTDM', caption: '', builder: 'equal', linkOpt: 'AND', value: '99' }
  ]));
  const ORDER = encodeURIComponent('-NJDM,+DWDM,+ZYDM');

  console.log('1/3 拉取方案列表…');
  let rows = [];
  let page = 1;
  let total = 0;
  while (true) {
    const j = await post(
      LIST,
      `querySetting=${querySetting}&*order=${ORDER}&pageSize=200&pageNumber=${page}`
    );
    const d = j && j.datas && j.datas.qxpyfacxzl;
    if (!d) {
      console.error('列表返回异常', j);
      return;
    }
    total = d.totalSize;
    rows = rows.concat(d.rows || []);
    console.log(`  列表 ${rows.length}/${total}`);
    if (rows.length >= total || !d.rows || !d.rows.length) break;
    page++;
    await sleep(150);
  }

  // 打印年级/类型分布，方便你确认 184 的筛选条件
  const byYear = {};
  const byType = {};
  rows.forEach(r => {
    byYear[r.NJDM_DISPLAY] = (byYear[r.NJDM_DISPLAY] || 0) + 1;
    byType[r.XDLXDM_DISPLAY] = (byType[r.XDLXDM_DISPLAY] || 0) + 1;
  });
  console.log('年级分布', byYear);
  console.log('类型分布', byType);

  const plans = rows.filter(r =>
    (!YEAR || r.NJDM_DISPLAY === YEAR) &&
    (!TYPE || r.XDLXDM_DISPLAY === TYPE)
  );
  console.log(`2/3 选中 ${plans.length} 个方案（${YEAR || '全部年级'} / ${TYPE || '全部类型'}）`);
  if (!plans.length) {
    console.warn('没有选中方案，请修改 YEAR/TYPE 后重跑');
    return;
  }

  const out = [];
  for (let i = 0; i < plans.length; i++) {
    const p = plans[i];
    try {
      const h = await post(BASE + '/jwapp/sys/jwpubapp/modules/pyfa/qxpyfacx.do',
        'PYFADM=' + encodeURIComponent(p.PYFADM));
      await sleep(60);
      const g = await post(BASE + '/jwapp/sys/jwpubapp/modules/pyfa/kzcx.do',
        'PYFADM=' + encodeURIComponent(p.PYFADM));
      await sleep(60);
      const c = await post(BASE + '/jwapp/sys/jwpubapp/modules/pyfa/kzkccx.do',
        'PYFADM=' + encodeURIComponent(p.PYFADM));
      out.push({
        PYFADM: p.PYFADM,
        name: p.PYFAMC,
        year: p.NJDM_DISPLAY,
        type: p.XDLXDM_DISPLAY,
        header: (h.datas && h.datas.qxpyfacx && h.datas.qxpyfacx.rows && h.datas.qxpyfacx.rows[0]) || null,
        groups: (g.datas && g.datas.kzcx && g.datas.kzcx.rows) || [],
        courses: (c.datas && c.datas.kzkccx && c.datas.kzkccx.rows) || []
      });
    } catch (e) {
      console.error('失败', p.PYFAMC, e);
      out.push({ PYFADM: p.PYFADM, name: p.PYFAMC, error: String(e) });
    }
    if (i % 5 === 0 || i === plans.length - 1) {
      console.log(`  详情 ${i + 1}/${plans.length} ${p.PYFAMC}`);
    }
    await sleep(120);
  }

  console.log('3/3 打包下载…');
  const blob = new Blob([JSON.stringify({
    fetchedAt: new Date().toISOString(),
    filter: { year: YEAR, type: TYPE },
    planCount: out.length,
    plans: out
  })], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `JLU_培养方案_${YEAR || '全部'}_${TYPE || '全部'}_${out.length}.json`;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  console.log('完成：', a.download);
})();
