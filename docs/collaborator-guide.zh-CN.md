# 给协作者的上手指南

这份文档写给想往 **DDB Skillhub** 里发布 skill 的人。你不需要加入组织，也不需要仓库的写权限 —— 任何人 fork 之后提 PR 就可以发布。

仓库地址：https://github.com/Didib-Lab/didib-skillhub

---

## 一、先搞清楚你要走哪条路

| 你的情况 | 走哪条路 | 需要加入组织吗 |
| --- | --- | --- |
| 想发布 / 修改 skill（绝大多数人） | **A. Fork + PR** | 不需要 |
| 需要长期直接推送、帮忙审 PR | **B. 加入组织当维护者** | 需要，且要管理员邀请 |

**建议所有人先走 A。** 走 A 发布成功几次之后，如果确实需要写权限，再让管理员给你开 B。原因：组织成员对仓库的默认权限是只读，加入组织并不会让你能直接 push，发布流程和走 A 完全一样 —— 所以为了"能上传"而加入组织是没有意义的。

---

## 二、路线 A：Fork + PR 发布一个 skill

### 第 1 步：Fork 仓库

1. 打开 https://github.com/Didib-Lab/didib-skillhub
2. 点右上角 **Fork**
3. Owner 选你自己的账号，点 **Create fork**

你现在有了一个自己的副本，例如 `你的用户名/didib-skillhub`，在那里你随便改。

### 第 2 步：把 skill 写出来

在你自己 fork 的仓库里，进入 `skills/` 目录，新建一个文件夹，命名规则**必须**是 kebab-case（小写字母、数字、单个连字符）：

```
skills/
└── pdf-table-extract/       ← 文件夹名
    ├── SKILL.md             ← 必须有
    ├── references/          ← 可选，放长文档
    └── scripts/             ← 可选，放脚本
```

只有 `SKILL.md` 是必需的。最省事的做法是**复制 `skills/hello-world` 整个文件夹**，重命名，然后改内容。

`SKILL.md` 长这样：

```markdown
---
name: pdf-table-extract
description: Extract tables from PDF files into CSV or Markdown, preserving merged cells. Use when the user provides a PDF and asks for its tabular data, or wants a spreadsheet built from a report.
tags:
  - pdf
  - data
---

# PDF Table Extract

## Instructions

1. 第一步……
2. 第二步……

## When NOT to use this skill

扫描件没有文字层时，先做 OCR。
```

**三条硬规则**（CI 会卡）：

1. `name` 必须和文件夹名**完全一致**，且是 kebab-case。
2. `description` 必须说明**做什么** + **什么时候用**（要有 "Use when ..." 这类触发语）。这一行是 agent 决定要不要加载你 skill 的唯一依据，写不好就等于没人用。
3. 文件夹里只能有 `SKILL.md`，加上 `references/`、`scripts/`、`assets/`、`agents/`、`evals/` 这几个目录。别放 `.DS_Store`、`notes.txt` 之类的东西。

### 第 3 步：本地自检（强烈建议）

```bash
git clone https://github.com/你的用户名/didib-skillhub.git
cd didib-skillhub
python scripts/validate_skills.py      # 必须 0 error
python scripts/build_catalog.py        # 更新 README 的 skill 表格
```

`build_catalog.py` 会改写 `README.md` 和 `skills.json`，**这两个改动要一起提交**，否则 CI 会报 "catalog is out of date"。

> 如果 `git clone` 或 `git push` 连不上 GitHub（公司网络/校园网常见），看本文最后的「网络问题」一节。

### 第 4 步：提交并推送

```bash
git checkout -b skill/pdf-table-extract
git add -A
git commit -m "feat(pdf-table-extract): add the PDF table extraction skill"
git push -u origin skill/pdf-table-extract
```

### 第 5 步：提 PR

1. 回到你自己的 fork 页面，会看到一个黄色的 **Compare & pull request** 按钮，点它
2. **确认 base 是 `Didib-Lab/didib-skillhub` 的 `main`**（很容易搞错成自己的 fork）
3. 填标题和说明。说明里请写：这个 skill 做什么、你用什么提示词测过、输出是什么
4. 勾选 PR 模板里的清单
5. 点 **Create pull request**

### 第 6 步：等 CI 和 review

PR 一开，CI 会自动跑：

| 检查 | 不过的原因 |
| --- | --- |
| Validate skills | 命名/frontmatter/目录结构不合规，或扫到疑似密钥 |
| Check the README catalog is up to date | 忘了跑 `build_catalog.py` |

CI 红了就照报错改，推新提交即可，PR 会自动更新。CI 绿了之后维护者会 review，通过就合并。

### 第 7 步：合并之后

你的 skill 会出现在 README 的表格里，别人就能一条命令装上了。你自己也能：

```bash
./scripts/install.sh install pdf-table-extract
```

---

## 三、路线 B：加入组织（仅维护者需要）

只有需要**直接推送到主仓库**或**帮忙审 PR / 合并**的人才需要这一步。

### 管理员怎么邀请

1. 打开 https://github.com/orgs/Didib-Lab/people
2. 点 **Invite member**
3. 填对方的 GitHub 用户名或邮箱
4. 选角色：
   - **Member** —— 普通成员，只是挂名，对仓库仍是只读
   - **Owner** —— 完全控制，包括删组织、改账单。**除你自己外不要给别人**
5. 点 **Send invitation**

### 被邀请的人怎么接受

1. 登录 GitHub，打开 https://github.com/orgs/Didib-Lab/invitation
2. 点 **Join Didib-Lab**

邀请会发到邮箱，**30 天不接受会自动过期**。

### 想让他能直接 push？还要再给一次权限

加入组织**不会**自动获得写权限（组织默认权限是 read）。必须额外做一步，二选一：

- **给整个仓库的写权限**：https://github.com/Didib-Lab/didib-skillhub/settings/access → **Add people** → 输入用户名 → 权限选 **Write**（或 Maintain）
- **只给某个仓库的权限（推荐）**：上面同一个页面，用 **Add teams** 先建一个 team（例如 `maintainers`）再授权，方便以后批量管理

`Write` 权限可以推分支、开 PR；`Maintain` 还能管 issue 和设置，但改不了敏感配置。

### 注意

`main` 分支已经开了保护：**不能强推、不能删除**，并且必须通过 `Validate skills` 检查。所以即使是 Write 权限的成员，也不应该直接往 `main` 推 —— 走分支 + PR，保持可追溯。

---

## 四、网络问题：git 连不上 GitHub

有些网络（公司代理、校园网、部分运营商）会拦住 git 用的 TLS 通道，症状是：

```
fatal: unable to access 'https://github.com/...': Failed to connect to
github.com port 443 after 21179 ms: Could not connect to server
```

但浏览器能打开 GitHub、`gh` 命令也能用。这时候：

**如果你只是要发布 skill**，完全不需要 git —— 直接在 GitHub 网页上编辑文件、用网页界面提 PR 就行（在 fork 里点开文件 → 铅笔图标 → 改 → Commit changes）。本文路线 A 的第 4、5 步用网页代替即可。

**如果必须用 git**，在仓库目录里跑诊断，它会告诉你是哪一层断了：

```powershell
./tools/diagnose-git-transport.ps1
```

如果诊断为 ".NET 通、git 不通"，用 API 发布（需要装 `gh` 并 `gh auth login`）：

```powershell
./tools/publish.ps1
```

---

## 五、速查

```bash
# 发布一个新 skill 的最短路径
cp -R skills/hello-world skills/my-skill    # 复制骨架
# 改 skills/my-skill/SKILL.md
python scripts/validate_skills.py           # 必须 0 error
python scripts/build_catalog.py             # 更新 README + skills.json
git checkout -b skill/my-skill && git add -A
git commit -m "feat(my-skill): add the ... skill"
git push -u origin skill/my-skill
# 然后在网页上向 Didib-Lab/didib-skillhub:main 提 PR
```

详细的写作规范在 [CONTRIBUTING.md](../CONTRIBUTING.md)，frontmatter 的完整字段和校验规则在 [docs/skill-format.md](../docs/skill-format.md)。
