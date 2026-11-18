class LexiconMeaning {
  const LexiconMeaning(this.modern, {this.condition, this.kind});
  final String modern;
  final String? condition;
  final String? kind;
}

class LexiconEntry {
  const LexiconEntry({
    required this.word,
    required this.meanings,
    this.kind = '实词',
    this.source = '内置高频文言词表（原创整理）',
    this.confidence = 0.8,
    this.pattern,
  });
  final String word;
  final List<LexiconMeaning> meanings;
  final String kind;
  final String source;
  final double confidence;
  final String? pattern;
}

const lexiconVersion = 'builtin-2026-11-1';

const builtinLexicon = <String, LexiconEntry>{
  '走': LexiconEntry(
    word: '走',
    meanings: [
      LexiconMeaning('跑', condition: '古义优先'),
      LexiconMeaning('逃跑'),
    ],
  ),
  '兵': LexiconEntry(
    word: '兵',
    meanings: [
      LexiconMeaning('士兵'),
      LexiconMeaning('军队'),
      LexiconMeaning('兵器'),
    ],
  ),
  '师': LexiconEntry(
    word: '师',
    meanings: [
      LexiconMeaning('军队'),
      LexiconMeaning('老师'),
      LexiconMeaning('学习'),
    ],
  ),
  '谢': LexiconEntry(
    word: '谢',
    meanings: [
      LexiconMeaning('道歉'),
      LexiconMeaning('推辞'),
      LexiconMeaning('感谢'),
      LexiconMeaning('告别'),
    ],
  ),
  '绝': LexiconEntry(
    word: '绝',
    meanings: [
      LexiconMeaning('断绝'),
      LexiconMeaning('停止'),
      LexiconMeaning('极、非常'),
    ],
  ),
  '假': LexiconEntry(
    word: '假',
    meanings: [LexiconMeaning('借'), LexiconMeaning('借助'), LexiconMeaning('假装')],
  ),
  '汤': LexiconEntry(
    word: '汤',
    meanings: [LexiconMeaning('热水'), LexiconMeaning('汤药')],
  ),
  '妻子': LexiconEntry(
    word: '妻子',
    meanings: [LexiconMeaning('妻子和子女'), LexiconMeaning('妻子')],
  ),
  '交通': LexiconEntry(
    word: '交通',
    meanings: [LexiconMeaning('交错相通'), LexiconMeaning('往来通达')],
  ),
  '牺牲': LexiconEntry(
    word: '牺牲',
    meanings: [LexiconMeaning('祭祀用的牲畜'), LexiconMeaning('舍弃生命')],
  ),
  '卑鄙': LexiconEntry(
    word: '卑鄙',
    meanings: [LexiconMeaning('身份低微、见识浅陋'), LexiconMeaning('品行恶劣')],
  ),
  '可以': LexiconEntry(
    word: '可以',
    meanings: [LexiconMeaning('可以凭借'), LexiconMeaning('能够')],
  ),
  '烈士': LexiconEntry(
    word: '烈士',
    meanings: [LexiconMeaning('有志向功业的人'), LexiconMeaning('殉难者')],
  ),
  '中国': LexiconEntry(
    word: '中国',
    meanings: [LexiconMeaning('中原地区'), LexiconMeaning('国家')],
  ),
  '非常': LexiconEntry(
    word: '非常',
    meanings: [LexiconMeaning('不同寻常的事变'), LexiconMeaning('很、十分')],
  ),
  '无论': LexiconEntry(word: '无论', meanings: [LexiconMeaning('不要说，更不必说')]),
  '所以': LexiconEntry(
    word: '所以',
    meanings: [
      LexiconMeaning('用来……的'),
      LexiconMeaning('原因'),
      LexiconMeaning('因此'),
    ],
  ),
  '亲戚': LexiconEntry(
    word: '亲戚',
    meanings: [LexiconMeaning('父母兄弟等内外亲属'), LexiconMeaning('姻亲')],
  ),
  '地方': LexiconEntry(
    word: '地方',
    meanings: [LexiconMeaning('土地方圆'), LexiconMeaning('处所')],
  ),
  '故事': LexiconEntry(
    word: '故事',
    meanings: [LexiconMeaning('旧事、先例'), LexiconMeaning('故事')],
  ),
  '学': LexiconEntry(
    word: '学',
    meanings: [LexiconMeaning('学习'), LexiconMeaning('学问')],
  ),
  '习': LexiconEntry(
    word: '习',
    meanings: [
      LexiconMeaning('温习'),
      LexiconMeaning('练习'),
      LexiconMeaning('习惯'),
    ],
  ),
  '说': LexiconEntry(
    word: '说',
    meanings: [
      LexiconMeaning('同“悦”，愉快', condition: '通假'),
      LexiconMeaning('说明'),
      LexiconMeaning('劝说'),
    ],
  ),
  '时': LexiconEntry(
    word: '时',
    meanings: [
      LexiconMeaning('按时'),
      LexiconMeaning('当时'),
      LexiconMeaning('时机'),
    ],
  ),
  '故': LexiconEntry(
    word: '故',
    meanings: [
      LexiconMeaning('所以'),
      LexiconMeaning('旧的'),
      LexiconMeaning('原因'),
      LexiconMeaning('故意'),
    ],
  ),
  '人': LexiconEntry(word: '人', meanings: [LexiconMeaning('人')]),
  '亲': LexiconEntry(
    word: '亲',
    meanings: [
      LexiconMeaning('亲近'),
      LexiconMeaning('父母'),
      LexiconMeaning('亲人'),
    ],
  ),
  '其': LexiconEntry(
    word: '其',
    meanings: [
      LexiconMeaning('他的/它的'),
      LexiconMeaning('那'),
      LexiconMeaning('大概'),
      LexiconMeaning('难道'),
    ],
    kind: '虚词',
  ),
  '之': LexiconEntry(
    word: '之',
    meanings: [
      LexiconMeaning('他/它'),
      LexiconMeaning('的'),
      LexiconMeaning('往、到'),
    ],
    kind: '虚词',
  ),
  '而': LexiconEntry(
    word: '而',
    meanings: [
      LexiconMeaning('并且'),
      LexiconMeaning('却'),
      LexiconMeaning('就'),
      LexiconMeaning('地'),
    ],
    kind: '虚词',
  ),
  '以': LexiconEntry(
    word: '以',
    meanings: [
      LexiconMeaning('用'),
      LexiconMeaning('因为'),
      LexiconMeaning('来'),
      LexiconMeaning('认为'),
    ],
    kind: '虚词',
  ),
  '于': LexiconEntry(
    word: '于',
    meanings: [
      LexiconMeaning('在'),
      LexiconMeaning('从'),
      LexiconMeaning('向'),
      LexiconMeaning('比'),
    ],
    kind: '虚词',
  ),
  '为': LexiconEntry(
    word: '为',
    meanings: [
      LexiconMeaning('是'),
      LexiconMeaning('做'),
      LexiconMeaning('被'),
      LexiconMeaning('为了'),
    ],
    kind: '虚词',
  ),
  '者': LexiconEntry(
    word: '者',
    meanings: [LexiconMeaning('……的人/事物'), LexiconMeaning('停顿')],
    kind: '虚词',
  ),
  '也': LexiconEntry(
    word: '也',
    meanings: [LexiconMeaning('判断语气'), LexiconMeaning('也')],
    kind: '虚词',
  ),
  '乃': LexiconEntry(
    word: '乃',
    meanings: [LexiconMeaning('于是'), LexiconMeaning('才'), LexiconMeaning('是')],
    kind: '虚词',
  ),
  '则': LexiconEntry(
    word: '则',
    meanings: [LexiconMeaning('就'), LexiconMeaning('却'), LexiconMeaning('那么')],
    kind: '虚词',
  ),
  '焉': LexiconEntry(
    word: '焉',
    meanings: [
      LexiconMeaning('于此'),
      LexiconMeaning('哪里'),
      LexiconMeaning('语气助词'),
    ],
    kind: '虚词',
  ),
  '乎': LexiconEntry(
    word: '乎',
    meanings: [LexiconMeaning('吗'), LexiconMeaning('呢'), LexiconMeaning('于')],
    kind: '虚词',
  ),
  '哉': LexiconEntry(
    word: '哉',
    meanings: [LexiconMeaning('呢'), LexiconMeaning('啊')],
    kind: '虚词',
  ),
  '矣': LexiconEntry(word: '矣', meanings: [LexiconMeaning('了')], kind: '虚词'),
  '夫': LexiconEntry(
    word: '夫',
    meanings: [LexiconMeaning('成年男子'), LexiconMeaning('句首发语词')],
    kind: '虚词',
  ),
  '盖': LexiconEntry(
    word: '盖',
    meanings: [LexiconMeaning('大概'), LexiconMeaning('原来是')],
    kind: '虚词',
  ),
  '虽': LexiconEntry(
    word: '虽',
    meanings: [LexiconMeaning('虽然'), LexiconMeaning('即使')],
    kind: '虚词',
  ),
  '若': LexiconEntry(
    word: '若',
    meanings: [LexiconMeaning('像'), LexiconMeaning('如果'), LexiconMeaning('你')],
    kind: '虚词',
  ),
  '所': LexiconEntry(
    word: '所',
    meanings: [LexiconMeaning('……的（人/事物）'), LexiconMeaning('处所')],
    kind: '虚词',
  ),
  '与': LexiconEntry(
    word: '与',
    meanings: [LexiconMeaning('和'), LexiconMeaning('给予'), LexiconMeaning('参与')],
    kind: '虚词',
  ),
  '因': LexiconEntry(
    word: '因',
    meanings: [
      LexiconMeaning('于是'),
      LexiconMeaning('凭借'),
      LexiconMeaning('因为'),
    ],
    kind: '虚词',
  ),
  '然': LexiconEntry(
    word: '然',
    meanings: [
      LexiconMeaning('这样'),
      LexiconMeaning('然而'),
      LexiconMeaning('……的样子'),
    ],
    kind: '虚词',
  ),
  '且': LexiconEntry(
    word: '且',
    meanings: [
      LexiconMeaning('况且'),
      LexiconMeaning('将要'),
      LexiconMeaning('暂且'),
    ],
    kind: '虚词',
  ),
  '何': LexiconEntry(
    word: '何',
    meanings: [
      LexiconMeaning('什么'),
      LexiconMeaning('为什么'),
      LexiconMeaning('怎么'),
    ],
    kind: '虚词',
  ),
  '安': LexiconEntry(
    word: '安',
    meanings: [
      LexiconMeaning('怎么'),
      LexiconMeaning('安定'),
      LexiconMeaning('安置'),
    ],
  ),
  '莫': LexiconEntry(
    word: '莫',
    meanings: [LexiconMeaning('没有人'), LexiconMeaning('不要')],
    kind: '虚词',
  ),
  '弗': LexiconEntry(word: '弗', meanings: [LexiconMeaning('不')], kind: '虚词'),
  '未': LexiconEntry(word: '未', meanings: [LexiconMeaning('没有')], kind: '虚词'),
  '无': LexiconEntry(word: '无', meanings: [LexiconMeaning('没有')], kind: '虚词'),
  '不': LexiconEntry(word: '不', meanings: [LexiconMeaning('不')], kind: '虚词'),
  '独': LexiconEntry(
    word: '独',
    meanings: [LexiconMeaning('只、仅仅'), LexiconMeaning('独自')],
  ),
  '廉颇': LexiconEntry(
    word: '廉颇',
    meanings: [LexiconMeaning('廉颇（人名）')],
    kind: '专名',
  ),
  '赵': LexiconEntry(word: '赵', meanings: [LexiconMeaning('赵国')], kind: '专名'),
  '良将': LexiconEntry(word: '良将', meanings: [LexiconMeaning('优秀将领')]),
  '蚓': LexiconEntry(word: '蚓', meanings: [LexiconMeaning('蚯蚓')]),
  '爪牙': LexiconEntry(
    word: '爪牙',
    meanings: [LexiconMeaning('爪子和牙齿'), LexiconMeaning('得力助手')],
  ),
  '筋骨': LexiconEntry(
    word: '筋骨',
    meanings: [LexiconMeaning('筋和骨头'), LexiconMeaning('身体')],
  ),
  '青': LexiconEntry(
    word: '青',
    meanings: [LexiconMeaning('靛青'), LexiconMeaning('蓝色/绿色')],
  ),
  '蓝': LexiconEntry(word: '蓝', meanings: [LexiconMeaning('蓝草')]),
  '取': LexiconEntry(
    word: '取',
    meanings: [LexiconMeaning('提取'), LexiconMeaning('攻取')],
  ),
  '身死': LexiconEntry(word: '身死', meanings: [LexiconMeaning('自己死亡')]),
  '天下': LexiconEntry(
    word: '天下',
    meanings: [LexiconMeaning('天下人'), LexiconMeaning('国家')],
  ),
  '笑': LexiconEntry(word: '笑', meanings: [LexiconMeaning('嘲笑')]),
  '王': LexiconEntry(
    word: '王',
    meanings: [LexiconMeaning('称王'), LexiconMeaning('君王')],
  ),
  '破': LexiconEntry(
    word: '破',
    meanings: [LexiconMeaning('攻破'), LexiconMeaning('打破')],
  ),
  '秦': LexiconEntry(word: '秦', meanings: [LexiconMeaning('秦国')], kind: '专名'),
  '咸阳': LexiconEntry(
    word: '咸阳',
    meanings: [LexiconMeaning('咸阳（地名）')],
    kind: '专名',
  ),
  '吾': LexiconEntry(word: '吾', meanings: [LexiconMeaning('我')], kind: '代词'),
  '师之': LexiconEntry(word: '师之', meanings: [LexiconMeaning('以他为老师')]),
  '是': LexiconEntry(
    word: '是',
    meanings: [LexiconMeaning('这'), LexiconMeaning('是')],
  ),
  '或': LexiconEntry(
    word: '或',
    meanings: [LexiconMeaning('有的人'), LexiconMeaning('或许')],
  ),
  '于蓝': LexiconEntry(word: '于蓝', meanings: [LexiconMeaning('从蓝草中')]),
  '者王': LexiconEntry(word: '者王', meanings: [LexiconMeaning('的人称王')]),
  '赵之良将': LexiconEntry(word: '赵之良将', meanings: [LexiconMeaning('赵国的优秀将领')]),
  '不亦': LexiconEntry(word: '不亦', meanings: [LexiconMeaning('不也是')]),
  '说乎': LexiconEntry(word: '说乎', meanings: [LexiconMeaning('愉快吗')]),
  '何陋': LexiconEntry(word: '何陋', meanings: [LexiconMeaning('有什么简陋')]),
  '有': LexiconEntry(word: '有', meanings: [LexiconMeaning('有')]),
};

const builtinPatterns = <String, String>{
  '不亦……乎': '不也是……吗',
  '无乃……乎': '恐怕……吧',
  '得无……乎': '莫非……吧',
  '何以……': '凭什么/为什么……',
  '何……之有': '有什么……呢',
  '何陋之有': '有什么简陋的呢',
  '为……所……': '被……所……',
  '见……于……': '被……',
  '以……为……': '把……当作……',
  '孰与': '与……相比，哪一个更……',
  '所以': '用来……的/……的原因',
  '无以': '没有用来……的办法',
  '有以': '有用来……的办法',
  '若……则……': '如果……就……',
  '虽……然……': '虽然……但是……',
};

final Map<String, LexiconEntry> localCustomLexicon = {};

LexiconEntry? lookupLexicon(String word) =>
    localCustomLexicon[word] ?? builtinLexicon[word];
