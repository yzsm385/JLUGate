/* 由 build_student_id_data.py 生成，请勿手改。 */
(function (root) {
  root.STUDENT_ID_PREFIXES = {
 "meta": {
  "title": "吉林大学 学号前缀 → 学院/单位 对照",
  "source": "用户提供的学号名单（2026-11-05）",
  "updated": "2026-11-05",
  "note": "名单给的是学号/邮箱里的专业（学院）代码；本科与研究生基本共用同一套代码，所以代码只能判断“该单位有没有本科”，不能判断某个学生是本科还是研究生。",
  "studentIDFormat": "代码(2–4位) + 入学年份(2位) + 班号(2位) + 班内序号(2位)；如 21230123 = 21 计算机、2023 级、01 班、23 号。代码在最前面，按最长匹配。",
  "suffixRule": "简称未以「学院/中心/学部/研究所/团委…」结尾时自动补「学院」；文学院、法学院、药学院、商学与管理学院、新闻与传播学院为固定写法。",
  "undergraduateRule": "undergraduate=true 表示该代码有本科专业，可参与绩点/推免测算；false 表示不招本科（行政单位、公共教学中心、继续教育、科研机构等）；null 表示待确认，不猜。",
  "duplicateCodes": {
   "25": [
    "环境与资源学院",
    "新能源与环境学院"
   ],
   "81": [
    "畜牧兽医学院",
    "动物医学学院"
   ]
  },
  "uncertainCodes": [
   "26",
   "34",
   "78",
   "81",
   "83",
   "JX49",
   "X1",
   "X2",
   "XX"
  ],
  "counts": {
   "all": 81,
   "undergraduate": 53,
   "nonUndergraduate": 19,
   "uncertain": 9
  }
 },
 "entries": [
  {
   "id": "01",
   "code": "01",
   "name": "哲学社会学院",
   "raw": "哲学社会",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "02",
   "code": "02",
   "name": "文学院",
   "raw": "文学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "03",
   "code": "03",
   "name": "外国语言文化学院",
   "raw": "外国语言文化",
   "aliases": [
    "外国语学院"
   ],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "04",
   "code": "04",
   "name": "艺术学院",
   "raw": "艺术",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "05",
   "code": "05",
   "name": "体育学院",
   "raw": "体育",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "06",
   "code": "06",
   "name": "经济学院",
   "raw": "经济",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "07",
   "code": "07",
   "name": "法学院",
   "raw": "法学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "08",
   "code": "08",
   "name": "行政学院",
   "raw": "行政",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "09",
   "code": "09",
   "name": "商学与管理学院",
   "raw": "商学与管理学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": "与 35、34 可能同院不同码（本科/研究生?），待确认"
  },
  {
   "id": "10",
   "code": "10",
   "name": "数学学院",
   "raw": "数学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "11",
   "code": "11",
   "name": "物理学院",
   "raw": "物理",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "12",
   "code": "12",
   "name": "化学学院",
   "raw": "化学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "13",
   "code": "13",
   "name": "生命科学学院",
   "raw": "生命科学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "14",
   "code": "14",
   "name": "机械与航空航天工程学院",
   "raw": "机械科学与工程、机械与航天空航天工程",
   "aliases": [
    "机械科学与工程学院",
    "机械与航空航天工程学院"
   ],
   "kind": "学院",
   "undergraduate": true,
   "note": "源名单把两个院名写在同一行；「航天空航天」疑为「航空航天」笔误，按同一代码处理"
  },
  {
   "id": "15",
   "code": "15",
   "name": "汽车工程学院",
   "raw": "汽车工程",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "16",
   "code": "16",
   "name": "材料科学与工程学院",
   "raw": "材料科学与工程",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "17",
   "code": "17",
   "name": "交通学院",
   "raw": "交通",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "18",
   "code": "18",
   "name": "生物与农业工程学院",
   "raw": "生物与农业工程",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "19",
   "code": "19",
   "name": "电子科学与工程学院",
   "raw": "电子科学与工程",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "20",
   "code": "20",
   "name": "通信工程学院",
   "raw": "通信工程",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "21",
   "code": "21",
   "name": "计算机科学与技术学院",
   "raw": "计算机科学与技术",
   "aliases": [
    "计算机学院"
   ],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "22",
   "code": "22",
   "name": "地球科学学院",
   "raw": "地球科学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "23",
   "code": "23",
   "name": "地球探测科学与技术学院",
   "raw": "地球探测科学与技术",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "24",
   "code": "24",
   "name": "建设工程学院",
   "raw": "建设工程",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "25",
   "code": "25",
   "name": "环境与资源学院",
   "raw": "环境与资源学院",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": "与 25 新能源与环境学院同码，疑为同一单位的新旧名称"
  },
  {
   "id": "25#2",
   "code": "25",
   "name": "新能源与环境学院",
   "raw": "新能源与环境",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "26",
   "code": "26",
   "name": "金融学院",
   "raw": "金融",
   "aliases": [],
   "kind": "学院",
   "undergraduate": null,
   "note": "全称与是否招本科待确认"
  },
  {
   "id": "27",
   "code": "27",
   "name": "公共卫生学院",
   "raw": "公共卫生",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "28",
   "code": "28",
   "name": "药学院",
   "raw": "药学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "29",
   "code": "29",
   "name": "护理学院",
   "raw": "护理",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "30",
   "code": "30",
   "name": "东北亚学院",
   "raw": "东北亚",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "31",
   "code": "31",
   "name": "历史文化学院",
   "raw": "历史文化",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "32",
   "code": "32",
   "name": "口腔医学院",
   "raw": "口腔医",
   "aliases": [
    "白求恩口腔医学院"
   ],
   "kind": "学院",
   "undergraduate": true,
   "note": "源名单写作「32、33 口腔医」，两码共用"
  },
  {
   "id": "33",
   "code": "33",
   "name": "口腔医学院",
   "raw": "口腔医",
   "aliases": [
    "白求恩口腔医学院"
   ],
   "kind": "学院",
   "undergraduate": true,
   "note": "源名单写作「32、33 口腔医」，两码共用"
  },
  {
   "id": "34",
   "code": "34",
   "name": "商学与管理学院（A）",
   "raw": "商学与管理学 A",
   "aliases": [],
   "kind": "学院",
   "undergraduate": null,
   "note": "「A」的含义（研究生/专业学位?）待确认"
  },
  {
   "id": "35",
   "code": "35",
   "name": "商学与管理学院",
   "raw": "商学与管理学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": "与 09、34 可能同院不同码，待确认"
  },
  {
   "id": "36",
   "code": "36",
   "name": "公共外交学院",
   "raw": "公共外交",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "37",
   "code": "37",
   "name": "新闻与传播学院",
   "raw": "新闻与传播学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "38",
   "code": "38",
   "name": "考古学院",
   "raw": "考古",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "39",
   "code": "39",
   "name": "马克思主义学院",
   "raw": "马克思主义",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "40",
   "code": "40",
   "name": "人工智能学院",
   "raw": "人工智能",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "50",
   "code": "50",
   "name": "预科教育学院",
   "raw": "预科教育",
   "aliases": [],
   "kind": "预科",
   "undergraduate": false,
   "note": "预科，不参与本科绩点/推免"
  },
  {
   "id": "54",
   "code": "54",
   "name": "应用技术学院",
   "raw": "应用技术",
   "aliases": [],
   "kind": "学院",
   "undergraduate": false,
   "note": "按专科/高职层次处理；若也招本科请改"
  },
  {
   "id": "55",
   "code": "55",
   "name": "软件学院",
   "raw": "软件",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "60",
   "code": "60",
   "name": "国际语言学院",
   "raw": "国际语言",
   "aliases": [],
   "kind": "学院",
   "undergraduate": false,
   "note": "留学生/语言进修，非本科；待确认"
  },
  {
   "id": "65",
   "code": "65",
   "name": "仪器科学与电气工程学院",
   "raw": "仪器科学与电气工程",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "70",
   "code": "70",
   "name": "临床医学院",
   "raw": "临床医",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": "通称；与 72–77 白求恩各临床医学院的对应关系待确认"
  },
  {
   "id": "71",
   "code": "71",
   "name": "基础医学院",
   "raw": "基础医",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "72",
   "code": "72",
   "name": "白求恩医学部第一临床医学院",
   "raw": "白求恩医学部第一临床医",
   "aliases": [
    "白求恩第一临床医学院"
   ],
   "kind": "学院",
   "undergraduate": true,
   "note": "官方写法：白求恩第一临床医学院；与 75 可能同院不同码，待确认"
  },
  {
   "id": "73",
   "code": "73",
   "name": "白求恩医学部第二临床医学院",
   "raw": "白求恩医学部第二临床医",
   "aliases": [
    "白求恩第二临床医学院"
   ],
   "kind": "学院",
   "undergraduate": true,
   "note": "官方写法：白求恩第二临床医学院；与 76 可能同院不同码，待确认"
  },
  {
   "id": "74",
   "code": "74",
   "name": "白求恩医学部第三临床医学院",
   "raw": "白求恩医学部第三临床医",
   "aliases": [
    "白求恩第三临床医学院"
   ],
   "kind": "学院",
   "undergraduate": true,
   "note": "官方写法：白求恩第三临床医学院；与 77 可能同院不同码，待确认"
  },
  {
   "id": "75",
   "code": "75",
   "name": "白求恩第一临床医学院",
   "raw": "白求恩第一临床医",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": "与 72 可能同院不同码，待确认"
  },
  {
   "id": "76",
   "code": "76",
   "name": "白求恩第二临床医学院",
   "raw": "白求恩第二临床医",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": "与 73 可能同院不同码，待确认"
  },
  {
   "id": "77",
   "code": "77",
   "name": "白求恩第三临床医学院",
   "raw": "白求恩第三临床医",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": "与 74 可能同院不同码，待确认"
  },
  {
   "id": "78",
   "code": "78",
   "name": "白求恩医学部基础医学院",
   "raw": "白求恩医学部基础医",
   "aliases": [],
   "kind": "学院",
   "undergraduate": null,
   "note": "与 71 基础医学院重名；是否研究生代码待确认"
  },
  {
   "id": "79",
   "code": "79",
   "name": "白求恩医学部",
   "raw": "白求恩医学部",
   "aliases": [],
   "kind": "学部",
   "undergraduate": false,
   "note": "学部机关，不直接招本科"
  },
  {
   "id": "81",
   "code": "81",
   "name": "畜牧兽医学院",
   "raw": "畜牧兽医",
   "aliases": [],
   "kind": "学院",
   "undergraduate": null,
   "note": "与 81 动物医学学院同码；旧称/是否仍招本科待确认"
  },
  {
   "id": "81#2",
   "code": "81",
   "name": "动物医学学院",
   "raw": "动物医学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "82",
   "code": "82",
   "name": "植物科学学院",
   "raw": "植物科学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "83",
   "code": "83",
   "name": "军需科技学院",
   "raw": "军需科技",
   "aliases": [],
   "kind": "学院",
   "undergraduate": null,
   "note": "是否仍招本科待确认"
  },
  {
   "id": "84",
   "code": "84",
   "name": "农学部公共教学中心",
   "raw": "农学部公共教学中心",
   "aliases": [],
   "kind": "教学单位",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "85",
   "code": "85",
   "name": "动物科学学院",
   "raw": "动物科学",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "87",
   "code": "87",
   "name": "食品科学与工程学院",
   "raw": "食品科学与工程",
   "aliases": [],
   "kind": "学院",
   "undergraduate": true,
   "note": ""
  },
  {
   "id": "90",
   "code": "90",
   "name": "创新创业教育学院",
   "raw": "创新创业教育",
   "aliases": [],
   "kind": "教学单位",
   "undergraduate": false,
   "note": "创新创业教育学院为教学单位，不招本科"
  },
  {
   "id": "91",
   "code": "91",
   "name": "公共外语教育学院",
   "raw": "公共外语教育",
   "aliases": [],
   "kind": "教学单位",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "92",
   "code": "92",
   "name": "公共体育教学与研究中心",
   "raw": "公共体育教学与研究中心",
   "aliases": [],
   "kind": "教学单位",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "93",
   "code": "93",
   "name": "公共数学教学与研究中心",
   "raw": "公共数学教学与研究中心",
   "aliases": [],
   "kind": "教学单位",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "94",
   "code": "94",
   "name": "公共物理教学与研究中心",
   "raw": "公共物理教学与研究中心",
   "aliases": [],
   "kind": "教学单位",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "95",
   "code": "95",
   "name": "公共化学教学与研究中心",
   "raw": "公共化学教学与研究中心",
   "aliases": [],
   "kind": "教学单位",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "96",
   "code": "96",
   "name": "公共计算机教学与研究中心",
   "raw": "公共计算机教学与研究中心",
   "aliases": [],
   "kind": "教学单位",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "99",
   "code": "99",
   "name": "团委",
   "raw": "团委（其他行政单位）",
   "aliases": [],
   "kind": "行政单位",
   "undergraduate": false,
   "note": "其他行政单位"
  },
  {
   "id": "199",
   "code": "199",
   "name": "本科生院",
   "raw": "本科生院",
   "aliases": [],
   "kind": "行政单位",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "JX",
   "code": "JX",
   "name": "继续教育学院",
   "raw": "继续教育",
   "aliases": [],
   "kind": "继续教育",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "JX49",
   "code": "JX49",
   "name": "莱姆顿学院",
   "raw": "莱姆顿",
   "aliases": [],
   "kind": "学院",
   "undergraduate": null,
   "note": "中外合作办学（莱姆顿学院）；层次待确认"
  },
  {
   "id": "L3",
   "code": "L3",
   "name": "原子与分子物理研究所",
   "raw": "原子与分子物理研究所",
   "aliases": [],
   "kind": "科研机构",
   "undergraduate": false,
   "note": "研究所，研究生/科研"
  },
  {
   "id": "LD",
   "code": "LD",
   "name": "劳动教育中心",
   "raw": "劳动教育中心",
   "aliases": [],
   "kind": "教学单位",
   "undergraduate": false,
   "note": ""
  },
  {
   "id": "X1",
   "code": "X1",
   "name": "经济信息学院",
   "raw": "经济信息",
   "aliases": [],
   "kind": "学院",
   "undergraduate": null,
   "note": "全称与层次待确认"
  },
  {
   "id": "X2",
   "code": "X2",
   "name": "工商管理学院",
   "raw": "工商管理",
   "aliases": [],
   "kind": "学院",
   "undergraduate": null,
   "note": "可能为 MBA/研究生层次，待确认"
  },
  {
   "id": "X3",
   "code": "X3",
   "name": "软件学院珠海",
   "raw": "软件学院珠海",
   "aliases": [],
   "kind": "学院",
   "undergraduate": false,
   "note": "研究生，目前不招本科（你提到可能 2027/2028 开始招，届时改 true）"
  },
  {
   "id": "XX",
   "code": "XX",
   "name": "所有学院",
   "raw": "所有",
   "aliases": [],
   "kind": "通配",
   "undergraduate": null,
   "note": "通配：任意学院"
  },
  {
   "id": "XZ27",
   "code": "XZ27",
   "name": "学生心理健康指导中心",
   "raw": "学生心理健康指导中心",
   "aliases": [],
   "kind": "行政单位",
   "undergraduate": false,
   "note": ""
  }
 ]
};
})(typeof window !== "undefined" ? window : globalThis);
