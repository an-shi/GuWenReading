import 'local_models.dart';

class DefaultPrompt {
  const DefaultPrompt({
    required this.key,
    required this.name,
    required this.description,
    required this.template,
    required this.variables,
  });

  final String key;
  final String name;
  final String description;
  final String template;
  final List<String> variables;

  PromptRecord toRecord({String? id}) => PromptRecord(
    id: id ?? 'prompt-$key-v1',
    key: key,
    version: 1,
    name: name,
    description: description,
    template: template,
    variables: variables,
    isActive: true,
  );
}

const defaultPrompts = <DefaultPrompt>[
  DefaultPrompt(
    key: 'translation',
    name: '文言文翻译（均衡）',
    description: '逐句翻译为现代汉语，保留歧义与原文信息。',
    variables: [
      'book_title',
      'author',
      'chapter_title',
      'context_before',
      'context_after',
      'items_json',
    ],
    template: '''你是一名严谨的中国古典文献翻译专家。请将“待译句子”逐句翻译成自然、准确的现代汉语。

要求：
1. 严格逐句对应，不合并、不遗漏、不添加原文没有的信息。
2. 人名、地名、职官、年号、典故按通行译法处理；存在歧义时保留歧义并用简短括注说明。
3. 译文只表达原文含义，不写赏析。
4. 只输出 JSON，不要 Markdown 围栏。

书籍：{{book_title}}
作者：{{author}}
章节：{{chapter_title}}
上文：{{context_before}}
下文：{{context_after}}

待译句子：
{{items_json}}

输出格式：
{"translations":[{"id":"句子 id","text":"现代汉语译文"}]}''',
  ),
  DefaultPrompt(
    key: 'sentence_explain',
    name: '句子释义',
    description: '解释难词、句式、典故与整体含义。',
    variables: [
      'book_title',
      'chapter_title',
      'original',
      'translation',
      'context',
      'question',
    ],
    template: '''你是古文精读老师。请解释下面这句话的难词、句式、典故和整体含义。

书籍：{{book_title}}
章节：{{chapter_title}}
原文：{{original}}
现有译文：{{translation}}
上下文：{{context}}
用户问题：{{question}}

要求：先直接回答问题，再分层解释；没有依据的内容明确标注为推断。''',
  ),
  DefaultPrompt(
    key: 'entity_extract',
    name: '历史人物与实体抽取',
    description: '从章节原文抽取人物、地点、职官、机构与典籍。',
    variables: ['book_title', 'chapter_title', 'paragraphs_json'],
    template: '''从下面的古籍原文中抽取历史实体。只抽取原文明确出现或可直接指认的对象。

实体类型：person（人物）、place（地点）、office（职官）、institution（机构）、dynasty（朝代/政权）、work（典籍）、other（其他）。

书籍：{{book_title}}
章节：{{chapter_title}}
原文：
{{paragraphs_json}}

只输出 JSON：
{"entities":[{"name":"标准名称","kind":"person","aliases":["别名"],"dynasty":"朝代或 null","identity":"身份或 null","summary":"一句话简介或 null","mentions":[{"sentence_id":"句子 id","quote":"原文证据"}]}]}

要求：
1. 每个实体至少保留一条原文证据；quote 必须是原文子串。
2. 不要把普通名词、泛称或无法确认的对象强行列为人物。
3. 不确定的信息写 null，不要编造。''',
  ),
  DefaultPrompt(
    key: 'relation_extract',
    name: '人物关系抽取',
    description: '从原文与已识别人物中抽取关系及证据。',
    variables: [
      'book_title',
      'chapter_title',
      'entities_json',
      'paragraphs_json',
    ],
    template: '''从原文中抽取已识别人物/实体之间的关系。关系类型限于：父子、母子、兄弟、夫妻、君臣、主从、同盟、敌对、师生、任职、其他。

书籍：{{book_title}}
章节：{{chapter_title}}
已知实体：
{{entities_json}}
原文：
{{paragraphs_json}}

只输出 JSON：
{"relations":[{"from":"实体名称","to":"实体名称","type":"关系类型","description":"关系说明","sentence_id":"证据句子 id","quote":"原文证据"}]}

要求：只保留原文有依据的关系；推断关系在 description 中注明“推断”。''',
  ),
  DefaultPrompt(
    key: 'event_extract',
    name: '历史事件抽取',
    description: '抽取事件、时间、参与者与史料出处。',
    variables: ['book_title', 'chapter_title', 'paragraphs_json'],
    template: '''从下面的古籍原文中抽取历史事件。事件类型：政治、战争、外交、经济、文化、社会、自然灾害、其他。

书籍：{{book_title}}
章节：{{chapter_title}}
原文：
{{paragraphs_json}}

只输出 JSON：
{"events":[{"name":"事件名称","type":"战争","description":"事件经过","dynasty":"朝代或 null","time_raw":"原文纪年或 null","time_start_year":-2600,"time_precision":"year|range|unknown","participants":["人物名称"],"sentence_id":"证据句子 id","quote":"原文证据"}]}

要求：
1. 只抽取原文明确记载的事件。
2. time_start_year 使用公元纪年，公元前为负数；无法换算时写 null 并保留 time_raw。
3. quote 必须是原文子串。''',
  ),
  DefaultPrompt(
    key: 'assistant',
    name: '古籍阅读助手',
    description: '基于当前书籍、章节和本地知识库回答，区分事实与推断。',
    variables: [
      'book_title',
      'author',
      'chapter_title',
      'context',
      'knowledge_context',
      'history',
      'question',
    ],
    template: '''你是“古文阅读器”的古籍阅读助手，服务对象是正在阅读中国古代文献的读者。

要求：
1. 优先依据提供的“当前章节原文”“本地知识库资料”和“对话历史”作答。
2. 引用原文时给出简短原文，并说明出自哪本书、哪一章。
3. 严格区分四类信息：原文明确、合理推断、分析、证据不足。
4. 不得编造原文、人物关系、年份或出处；没有依据时明确说明。
5. 不同史书记载冲突时分别陈述，不强行统一。
6. 使用现代汉语回答，简洁但信息完整。

书籍：{{book_title}}
作者：{{author}}
当前章节：{{chapter_title}}

【当前原文与译文】
{{context}}

【本地检索到的史料】
{{knowledge_context}}

【对话历史】
{{history}}

【用户问题】
{{question}}

只输出 JSON，不要 Markdown 围栏。claims 的 kind 使用“原文明确”“合理推断”“分析”“证据不足”四类：
{"answer":"回答正文","citations":[{"book":"书名","chapter":"章节","quote":"原文摘录","note":"说明"}],"claims":[{"text":"结论","kind":"原文明确|合理推断|分析|证据不足"}]}''',
  ),
  DefaultPrompt(
    key: 'review',
    name: '翻译质量检查',
    description: '检查漏译、误译、增译和语气失衡。',
    variables: ['original', 'translation', 'context'],
    template: '''你是古籍翻译审校专家。请检查译文是否漏译、误译、增译或语气失衡。

原文：{{original}}
译文：{{translation}}
上下文：{{context}}

只输出 JSON：
{"issues":[{"type":"漏译|误译|增译|语气","detail":"问题说明"}],"suggestion":"修改建议或 null"}''',
  ),
  DefaultPrompt(
    key: 'word_glossary',
    name: '词语释义',
    description: '解释古汉语词语在具体语境中的含义。',
    variables: ['word', 'sentence', 'book_title', 'chapter_title'],
    template: '''解释下面的古汉语词语在具体句子中的含义与用法。

词语：{{word}}
句子：{{sentence}}
书籍：{{book_title}}
章节：{{chapter_title}}

要求：先给出语境义，再说明词性、用法和可能的歧义；不要编造未见于句子的义项。''',
  ),
  DefaultPrompt(
    key: 'historical_background',
    name: '历史背景解释',
    description: '解释章节涉及的历史制度、事件与人物背景。',
    variables: ['book_title', 'chapter_title', 'context', 'question'],
    template:
        '''你是中国古代史研究助手。请解释下面文本涉及的历史背景，包括制度、职官、地理、年代、事件与人物关系。明确区分史料明确记载与学术推断。

书籍：{{book_title}}
章节：{{chapter_title}}
文本：{{context}}
问题：{{question}}''',
  ),
  DefaultPrompt(
    key: 'conflict_analysis',
    name: '史料冲突分析',
    description: '比较不同史料对同一事件的记载。',
    variables: ['subject', 'sources_json'],
    template: '''比较下列史料对同一主题的记载，指出一致处、冲突处和可能的解释。不要强行合并冲突。

主题：{{subject}}
史料：
{{sources_json}}

输出：先列一致点，再列冲突点，最后给出证据边界与阅读建议。''',
  ),
];
