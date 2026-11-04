# 吉大站点目录（实测记录）

> 说明：域名后缀是 **jlu.edu.cn**（不是 jou.edu.cn）。下表每个域名都用 `curl` 实测过，
> 括号里是返回的页面标题，用来确认它确实是那个系统。

| 域名 | HTTP | 页面标题 | 用途 | 访问范围 |
|---|---|---|---|---|
| www.jlu.edu.cn | 200 | 吉林大学 | 主页 | 公网 |
| news.jlu.edu.cn | 200 | 吉林大学新闻中心网站 | 新闻 | 公网 |
| mails.jlu.edu.cn | 200 | 吉林大学学生邮箱 | 学生邮箱 | 公网 |
| mail.jlu.edu.cn | 200 | 吉林大学教师邮件系统 | 教师邮箱 | 公网 |
| iedu.jlu.edu.cn | 302 | 智慧校园 | 教务/选课/成绩 | 仅校内 |
| oa.jlu.edu.cn | 302 | 吉林大学电子校务平台 | 公文审批 | 仅校内 |
| ehall.jlu.edu.cn | 302 | 智慧校园 | 办事大厅 | 仅校内 |
| cas.jlu.edu.cn | 302 | 智慧校园 | 统一身份认证 | 仅校内 |
| ip.jlu.edu.cn | 200 | 校园网 IP 资源管理系统 | 在线设备/网费/解绑 | 仅校内 |
| lib.jlu.edu.cn | 200 | 吉林大学图书馆 | 借阅/数据库 | 页面公网、资源需 VPN |
| jwc.jlu.edu.cn | 200 | 吉林大学本科生院 | 教学通知 | 公网 |
| yjsy.jlu.edu.cn | 200 | 研究生院 | 培养/学位 | 公网 |
| nic.jlu.edu.cn | 200 | 大数据和网络管理中心 | 断网通知/报修 | 公网 |
| vpn.jlu.edu.cn | 302 | — | WebVPN（校外入口） | 公网 |

另有 `sso.jlu.edu.cn`、`yjs.jlu.edu.cn` 同属智慧校园体系，保留在候选、未单列。

参考：
- [WebVPN 使用指南（大数据和网络管理中心）](http://nic.jlu.edu.cn/info/1018/2148.htm)
- [研究生院登录问题说明](http://yjsy.jlu.edu.cn/info/1055/5494.htm)
