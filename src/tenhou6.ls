require! {
  assert
  './pai': Pai
  './wall': splitWall
  './util': {OTHER_PLAYERS, invert, ceilTo}
  './agari': {getBasicPoints, getBasicPointsYakuman}
}


# one entry in incoming/outgoing array

# building blocks

const PAI = with {
  11:\1m 12:\2m 13:\3m 14:\4m 15:\5m 16:\6m 17:\7m 18:\8m 19:\9m 51:\0m
  21:\1p 22:\2p 23:\3p 24:\4p 25:\5p 26:\6p 27:\7p 28:\8p 29:\9p 52:\0p
  31:\1s 32:\2s 33:\3s 34:\4s 35:\5s 36:\6s 37:\7s 38:\8s 39:\9s 53:\0s
  41:\1z 42:\2z 43:\3z 44:\4z 45:\5z 46:\6z 47:\7z
}
  for k, v of .. => ..[k] = Pai[v]
  ..[60] = \tsumokiri
  ..[0] = \daiminkan
const PAI_INV = {[v, Number k] for k, v of PAI}

export function parsePai(x)
  if x >= 0 then PAI[x] else null
export function parseRiichi(x)
  m = x.match /r(\d\d)/
  if (p = m?.1) then PAI[p] else null

export FUURO_RE = //
  ([cpmk])?(\d\d)  # 1 2 chi/pon/daiminkan/kakan
   ([pmk])?(\d\d)? # 3 4 pon/daiminkan/kakan
    ([pk])?(\d\d)? # 5 6 pon/kakan
    ([ma])?(\d\d)? # 7 8 daiminkan/ankan
//
export function parseFuuro(player, x)
  m = x.match FUURO_RE
  switch
  | type = m.1 => otherPai = m.2 ; ownPai = m[4 6 8] ; rel = 3
  | type = m.3 => otherPai = m.4 ; ownPai = m[2 6 8] ; rel = 2
  | type = m.5 => otherPai = m.6 ; ownPai = m[2 4 8] ; rel = 1
  | type = m.7 => otherPai = m.8 ; ownPai = m[2 4 6] ; rel = 1 # NOT TYPO
  | _ => return null
  ownPai = ownPai .filter (?) .map (PAI.)
  otherPai = PAI[otherPai]
  fromPlayer = (player + rel)%4
  switch type
  | \c =>
    if otherPai.succ.equivPai == ownPai.0.equivPai
      pai = otherPai.equivPai
    else
      pai = ownPai.0.equivPai
    {
      type: \chi, player
      details: {
        type: \minjun
        pai, ownPai, otherPai, fromPlayer
      }
    }
  | \p =>
    {
      type: \pon, player
      details: {
        type: \minko
        pai: otherPai.equivPai, ownPai, otherPai, fromPlayer
      }
    }
  | \m =>
    {
      type: \kan, player
      details: {
        type: \daiminkan
        pai: otherPai.equivPai, ownPai, otherPai, fromPlayer
      }
    }
  | \k =>
    kakanPai = otherPai # meh
    otherPai = ownPai.splice(3 - rel, 1).0
    {
      type: \kan, player
      details: {
        type: \kakan
        pai: otherPai.equivPai, ownPai, otherPai, fromPlayer, kakanPai
      }
    }
  | \a =>
    ownPai
      ..push otherPai
      ..sort Pai.compare
    {
      type: \kan, player
      details: {
        type: \ankan
        pai: otherPai.equivPai, ownPai
      }
    }
  | _ => null

export FUURO_INV =
  minjun: \c, minko: \p
  daiminkan: \m, kakan: \k, ankan: \a
export makeFuuro = ({type: aType, player, details: {
  type, pai, ownPai, otherPai, fromPlayer, kakanPai
}}) ->
  ownPai .= map (PAI_INV.)
  otherPai = PAI_INV[otherPai] ? ''
  kakanPai = PAI_INV[kakanPai] ? ''
  rel = (fromPlayer - player + 4)%4
  if type == \ankan or (aType == \kan and rel == 1) then rel = 0
  i = 3 - rel
  ownPai[0 til i]*'' + FUURO_INV[type] + kakanPai + otherPai + ownPai[i til]*''


# entry => action (might be incomplete)
export parseIncoming = (player, x) -->
  switch
  | pai = parsePai x =>
    {type: \tsumo, player, details: {pai, -rinshan}}
    # incomplete: cannot tell rinshan yet
  | a = parseFuuro player, x => a
  | _ => null
export parseOutgoing = (player, x) -->
  switch
  | pai = parsePai x =>
    switch pai
    | \daiminkan =>
      {type: \daiminkan} # dummy entry (next should be rinshan tsumo)
    | \tsumokiri =>
      {type: \dahai, player, details: {+tsumokiri, -riichi}}
      # incomplete: cannot tell what pai
    | _ =>
      {type: \dahai, player, details: {-tsumokiri, -riichi, pai}}
  | pai = parseRiichi x =>
    switch pai
    | \tsumokiri =>
      {type: \dahai, player, details: {+tsumokiri, +riichi}}
      # incomplete: cannot tell what pai
    | _ =>
      {type: \dahai, player, details: {-tsumokiri, +riichi, pai}}
  | a = parseFuuro player, x => a
  | _ => null

# action => entry
# NOTE:
export function makeIncoming(action)
  switch action.type
  | \tsumo => PAI_INV[action.details.pai]
  | \chi, \pon => makeFuuro action
  | \kan =>
    switch action.details.type
    | \daiminkan => makeFuuro action
    | _ => null
  | _ => null
export function makeOutgoing(action)
  switch action.type
  | \dahai =>
    {pai, tsumokiri, riichi} = action.details
    if tsumokiri then pai = \tsumokiri
    x = PAI_INV[pai]
    if riichi then "r#x" else x
  | \kan =>
    switch action.details.type
    | \daiminkan => 0 # dummy entry (see above)
    | \ankan, \kakan => makeFuuro action
    | _ => null
  | _ => null


# metadata (lots of hard-coded strings and regexps ahead!)

# rule array/string <=> riichi-core rulevar override object
const RULE_RE = /(東|南)(喰)?/
export function parseRule({disp, aka, aka51, aka52, aka53})
  disp ?= '南喰'
  if not isNaN(aka = parseInt aka)
    akahai = [aka, aka, aka]
  else
    akahai = [aka51, aka52, aka53].map parseInt
  if (m = disp.match RULE_RE)
    switch m.1
    | '東' => end = {normal: 1, overtime: 2} # east only
    | '南' => end = {normal: 2, overtime: 3} # east + south
    kuitan = !!m.2
  return {
    dora: {akahai}
    yaku: {kuitan}
    setup: {end}
  }
export function makeRule(rulevar)
  ret = {disp: 'riichi-core'}
  {akahai: [am, ap, as]} = rulevar.dora
  if am == ap == as
    ret.aka = am
  else
    ret.aka51 = am ; ret.aka52 = ap ; ret.aka53 = as
  ret

# delta/agari arrays <=> riichi-core agari output object
const AGARI_FU_HAN_RE = /^(\d+)符(\d+)飜/
const AGARI_MANGAN_RE = /^(満貫|跳満|倍満|三倍満|役満)/
const AGARI_YAKU_STR_RE = /^([^()]+)\((\d+)飜/
const AGARI_YAKUMAN_STR_RE = /^([^()]+)\(役満/
const AGARI_MANGAN_DICT =
  '満貫'  : 2000
  '跳満'  : 3000
  '倍満'  : 4000
  '三倍満': 6000
  '役満'  : 8000
const AGARI_DORA_DICT =
  'ドラ'  : \dora
  '赤ドラ': \akaDora
  '裏ドラ': \uraDora
const AGARI_YAKU_DICT =
  '門前清自摸和'  : \menzenchintsumohou
  '立直'          : \riichi
  '一発'          : \ippatsu
  '槍槓'          : \chankan
  '嶺上開花'      : \rinshankaihou
  '海底摸月'      : \haiteiraoyue
  '河底撈魚'      : \houteiraoyui
  '平和'          : \pinfu
  '断幺九'        : \tanyaochuu
  '一盃口'        : \iipeikou
  '自風 東'       : \jikazehai
  '自風 南'       : \jikazehai
  '自風 西'       : \jikazehai
  '自風 北'       : \jikazehai
  '場風 東'       : \bakazehai
  '場風 南'       : \bakazehai
  '場風 西'       : \bakazehai
  '場風 北'       : \bakazehai
  '役牌 白'       : \sangenpaiHaku
  '役牌 發'       : \sangenpaiHatsu
  '役牌 中'       : \sangenpaiChun
  '両立直'        : \doubleRiichi
  '七対子'        : \chiitoitsu
  '混全帯幺九'    : \honchantaiyaochuu
  '一気通貫'      : \ikkitsuukan
  '三色同順'      : \sanshokudoujun
  '三色同刻'      : \sanshokudoukou
  '三槓子'        : \sankantsu
  '対々和'        : \toitoihou
  '三暗刻'        : \sannankou
  '小三元'        : \shousangen
  '混老頭'        : \honraotou
  '二盃口'        : \ryanpeikou
  '純全帯幺九'    : \junchantaiyaochuu
  '混一色'        : \honniisou
  '清一色'        : \chinniisou
  '天和'          : \tenhou
  '地和'          : \chiihou
  '大三元'        : \daisangen
  '四暗刻'        : \suuankou
  '四暗刻単騎'    : \suuankouTanki
  '字一色'        : \tsuuiisou
  '緑一色'        : \ryuuiisou
  '清老頭'        : \chinraotou
  '九蓮宝燈'      : \chuurenpoutou
  '純正九蓮宝燈'  : \junseichuurenpoutou
  '国士無双'      : \kokushi
  '国士無双１３面': \kokushi13
  '大四喜'        : \daisuushi
  '小四喜'        : \shousuushi
  '四槓子'        : \suukantsu
export function parseAgari(delta, details)
  if !delta? then return null
  if details
    [x, y, z, pointStr, ...yakuStrList] = details

  if y == z
    isTsumo = true
    isRon = false
    player = z
  else
    isTsumo = false
    isRon = true
    player = z
    houjuuPlayer = y

  dora = {dora: 0, akaDora: 0, uraDora: 0}
  doraTotal = 0
  yaku = []
  yakuTotal = 0
  yakuman = []
  yakumanTotal = 0

  for yakuStr in yakuStrList
    if (m = yakuStr.match AGARI_YAKU_STR_RE)
      name = m.1
      han = parseInt m.2
      if (d = AGARI_DORA_DICT[name])
        dora[d] += han
        doraTotal += han
      else
        name = AGARI_YAKU_DICT[name]
        yaku.push {name, han}
        yakuTotal += han
    else if (m = yakuStr.match AGARI_YAKUMAN_STR_RE)
      name = m.1
      name = AGARI_YAKU_DICT[name]
      yakuman.push {name, times: 1}
      yakumanTotal++

  # TODO: cap yakumanTotal according to rulevar

  if (m = pointStr.match AGARI_FU_HAN_RE)
    fu = parseInt m.1
    han = parseInt m.2
    assert.equal han, doraTotal + yakuTotal,
      'han should be consistent with agari details'
    basicPoints = getBasicPoints {han, fu}
  else if (m = pointStr.match AGARI_MANGAN_RE)
    if yakumanTotal
      basicPoints = getBasicPointsYakuman yakumanTotal
    else
      han = doraTotal + yakuTotal
      basicPoints = AGARI_MANGAN_DICT[m.1]
  else throw Error 'bad agari description'

  return {
    isTsumo, isRon, delta
    player, houjuuPlayer
    han, fu, basicPoints
    dora, doraTotal
    yaku, yakuTotal, yakuman, yakumanTotal
  }

const AGARI_MANGAN_DICT_INV = invert AGARI_MANGAN_DICT
const AGARI_DORA_DICT_INV = invert AGARI_DORA_DICT
const AGARI_YAKU_KAZE = <[東 南 西 北]> #
const AGARI_YAKU_DICT_INV = invert AGARI_YAKU_DICT
export function makeAgari({
  chancha, bakaze
}:startState, {
  isTsumo, isRon, delta
  player, houjuuPlayer
  han, fu, basicPoints, dora
  yaku, yakuman, yakumanTotal
}:agari)

  jikaze = (4 + player - chancha)%4

  if basicPoints < 2000
    pointStr = "#{fu}符#{han}飜"
  else if basicPoints >= 8000
    pointStr = "役満"
  else
    pointStr = AGARI_MANGAN_DICT_INV[basicPoints]
  # parallel code borrowed from `./agari`:`getDelta`
  # NOTE: pointStr excludes honba
  [tsumoKoKo, tsumoOyaKo, ronKo, ronOya] = [1 2 4 6].map ->
    basicPoints*it |> ceilTo _, 100
  if isRon
    x = z = player ; y = houjuuPlayer
    if player == chancha
      pointStr += "#{ronOya}点"
    else # ko
      pointStr += "#{ronKo}点"
  else # tsumo
    x = y = z = player
    if player == chancha
      pointStr += "#{tsumoOyaKo}点∀" # \u2200 'for all'
    else # ko
      pointStr += "#{tsumoKoKo}-#{tsumoOyaKo}点"
  ret = [x, y, z, pointStr]
  for {name, han} in yaku
    name = switch name
    | \jikazehai => '自風 ' + AGARI_YAKU_KAZE[jikaze]
    | \bakazehai => '場風 ' + AGARI_YAKU_KAZE[bakaze]
    | _ => AGARI_YAKU_DICT_INV[name]
    ret.push "#{name}(#{han}飜)"
  for {name} in yakuman
    name = AGARI_YAKU_DICT_INV[name]
    ret.push "#{name}(役満)"
  if not yakumanTotal
    # NOTE: sequence must be guaranteed
    for name in <[dora akaDora uraDora]>
      if (han = dora[name])
        name = AGARI_DORA_DICT_INV[name]
        ret.push "#{name}(#{han}飜)"
  ret

# result array <=> riichi-core result object
# NOTE: the following cannot be inferred from log:
# - delta due to kyoutaku
# - kyoutaku
# - renchan
const RYOUKYOKU_DICT =
  '流局'    : \howanpai
  '流し満貫': \nagashiMangan
  '九種九牌': \kyuushuukyuuhai
  '三家和了': \tripleRon
  '四風連打': \suufonrenta
  '四家立直': \suuchariichi
  '四槓散了': \suukaikan
export function parseResult([type]:result)
  if type == '和了'
    agari1 = parseAgari result.1, result.2
    if agari1.isTsumo
      return {
        type: \tsumoAgari
        delta: agari1.delta
        details: agari1
      }
    else # ron
      agariList = [agari1]
      delta = agari1.delta.slice!
      if (agari2 = parseAgari result.3, result.4)
        agariList.push agari2
        for i til 4 => delta[i] += agari2.delta[i]
      if (agari3 = parseAgari result.5, result.6)
        agariList.push agari3
        for i til 4 => delta[i] += agari3.delta[i]
      return {
        type: \ron
        delta
        details: agariList
      }
  else if (reason = RYOUKYOKU_DICT[type])
    return {
      type: \ryoukyoku
      delta: result.1 ? [0 0 0 0]
      details: reason
    }
  else
    ... # TODO: lack of result

const RYOUKYOKU_DICT_INV = invert RYOUKYOKU_DICT
export function makeResult(startState, {type, delta, details})
  switch type
  | \tsumoAgari =>
    details = makeAgari startState, details
    ['和了', delta, details]
  | \ron =>
    with ['和了']
      for a in details
        ..push a.delta, makeAgari startState, a
  | \ryoukyoku =>
    switch details
    | \howanpai, \nagashiMangan =>
      [RYOUKYOKU_DICT_INV[details], delta]
    | _ =>
      [RYOUKYOKU_DICT_INV[details]]


# whole kyoku (one entry in `.log`)

export function parseKyoku([
  [nKyoku, honba, kyoutaku]
  points
  doraHyouji
  uraDoraHyouji
  hai0, inc0, out0
  hai1, inc1, out1
  hai2, inc2, out2
  hai3, inc3, out3
  rawResult
  # extra metadata embedded by riichi-core:
  #   wall: actual wall (all tiles known)
  extra
], {rulevar, seq})

  bakaze = nKyoku.>>.2 # floor div 4
  chancha = nKyoku%4
  startState = {seq, bakaze, chancha, honba, kyoutaku, points}

  # parse each component
  doraHyouji .= map (PAI.)
  uraDoraHyouji .= map (PAI.)
  hai0 .= map (PAI.)
  hai1 .= map (PAI.)
  hai2 .= map (PAI.)
  hai3 .= map (PAI.)
  hai = [hai0, hai1, hai2, hai3]
  inc0 .= map parseIncoming 0
  inc1 .= map parseIncoming 1
  inc2 .= map parseIncoming 2
  inc3 .= map parseIncoming 3
  inc = [inc0, inc1, inc2, inc3]
  out0 .= map parseOutgoing 0
  out1 .= map parseOutgoing 1
  out2 .= map parseOutgoing 2
  out3 .= map parseOutgoing 3
  out = [out0, out1, out2, out3]
  {delta} = result = parseResult rawResult

  # wall reconstruction if not included (see `./wall`)
  # - haipai: pre-populated
  # - piipai: pushed to wall as log replays
  # - ura/doraHyouji: assigned to wall at end
  # - rinshan:
  #   - pushed to separate array as log replays
  #   - assigned to wall at end
  #
  # There might be slots in the wall whose order cannot be inferred from log.
  # Set of these unknown pai is the complement of known pai (w.r.t. all pai).
  # For completeness, they are reconstructed in arbitrary order.
  #
  # Even in the case actual wall is embedded, recontructed wall is checked
  # against it to ensure integrity.

  # rearrange: hai0/1/2/3 => E/S/W/N
  [hai0, hai1, hai2, hai3] = hai[chancha til 4] ++ hai[0 til chancha]
  wall = [
    hai0[0], hai0[1], hai0[2], hai0[3], hai1[0], hai1[1], hai1[2], hai1[3],
    hai2[0], hai2[1], hai2[2], hai2[3], hai3[0], hai3[1], hai3[2], hai3[3],
    hai0[4], hai0[5], hai0[6], hai0[7], hai1[4], hai1[5], hai1[6], hai1[7],
    hai2[4], hai2[5], hai2[6], hai2[7], hai3[4], hai3[5], hai3[6], hai3[7],
    hai0[8], hai0[9], hai0[10], hai0[11], hai1[8], hai1[9], hai1[10], hai1[11],
    hai2[8], hai2[9], hai2[10], hai2[11], hai3[8], hai3[9], hai3[10], hai3[11],
    hai0[12], hai1[12], hai2[12], hai3[12]
  ]
  rinshan = []

  # replay the log
  p = chancha
  lastAction = {type: null}
  actionLog = []
  publishAction = (action) ->
    action.seq = ++seq
    lastAction := action
    actionLog.push action

  loop
    i = inc[p].shift!
    if !i? then break
    if i.type == \tsumo
      tsumohai = i.details.pai
      if lastAction.type != \kan
        wall.push tsumohai
        i.details.rinshan = false
      else
        rinshan.push tsumohai
        i.details.rinshan = true
    publishAction i

    o = out[p].shift!
    if !o? then break
    switch o.type
    | \daiminkan => continue # dummy -- don't publish
    | \dahai =>
      with o.details
        if ..tsumokiri then ..pai = tsumohai
        if ..riichi
          delta[p] -= 1000
          kyoutaku++
      p2 = (p + 1)%4
      for q in OTHER_PLAYERS[p]
        with inc[q][0]
          if ..? and ..type != \tsumo
          and ..details.fromPlayer == p
          and ..details.otherPai == o.details.pai
            p2 = q
            break
      p = p2
    publishAction o

  # special: check for unsuccessful riichi
  if lastAction.type == \dahai and lastAction.details.riichi
  and result.type == \ron
    delta[lastAction.player] += 1000
    kyoutaku--

  # complete the wall
  wall[134 135 132 133 ] = rinshan # NOTE: different from `./wall`
  wall[130 to 122 by -2] = doraHyouji
  wall[131 to 123 by -2] = uraDoraHyouji

  if (origWall = extra?.wall)
    # check inferred against actual wall
    for p, i in wall when p
      assert.equal p, origWall[i],
        'provided/reconstructed wall should be consistent'
    wall = origWall
  else
    # find and fill in unknown pai
    # NOTE: black magic two-liner basically does multi-set difference
    all = Pai.makeAll rulevar.dora.akahai # already sorted
    known = wall .filter (?) .sort Pai.compare
    i = 0
    unknown = [.. for all when .. != known[i] or (++i and 0)]
    wall = [.. ? unknown.pop! for wall]

  if result.type != \ryoukyoku then kyoutaku = 0
  result.kyoutaku = kyoutaku

  return {
    startState
    wall
    actionLog
    result
  }
export function makeKyoku({
  startState
  wall
  actionLog
  result
})
  # mostly borrowed from `./kyoku`:`Kyoku::constructor`
  {seq, bakaze, chancha, honba, kyoutaku, points} = startState
  nKyoku = bakaze*4 + chancha
  {haipai, rinshan, doraHyouji, uraDoraHyouji} = splitWall wall
  doraHyouji .= map (PAI_INV.)
  uraDoraHyouji .= map (PAI_INV.)
  jikaze = [(4 + i - chancha)%4 for i til 4]
  hai = [haipai[jikaze[i]].map (PAI_INV.) for i til 4]

  inc = [[] [] [] []]
  out = [[] [] [] []]
  for {player}:action in actionLog
    if (i = makeIncoming action)? then inc[player].push i
    if (o = makeOutgoing action)? then out[player].push o
  rawResult = makeResult startState, result

  [
    [nKyoku, honba, kyoutaku]
    points
    doraHyouji
    uraDoraHyouji
    hai.0, inc.0, out.0
    hai.1, inc.1, out.1
    hai.2, inc.2, out.2
    hai.3, inc.3, out.3
    rawResult
    extra: {wall}
  ]


export function parseGame({
  name: handles
  rule
  log
  # extra metadata embedded by riichi-core
  rulevar
})
  rulevar ?= parseRule rule
  log = for k, i in log
    parseKyoku k, {rulevar, seq: i*10000}
  return {handles, rulevar, log}

export function makeGame({
  handles: name
  rulevar
  log
})
  rule = makeRule rulevar
  log = for k in log
    makeKyoku k
  return {title: ['', ''], name, rule, rulevar, log}