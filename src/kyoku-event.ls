require! {
  'chai': {assert}

  './pai': Pai
  './wall': splitWall
  './util': {OTHER_PLAYERS}

  './kyoku-player-hidden': PlayerHidden
  './kyoku-player-hidden-mock': PlayerHiddenMock
}

# GLOBAL TODO:
# - explain doraHyouji piggybacking
# - refactor 99/tsumo/ron


# helpers for piggy-backing doraHyouji handling on events {{{

# master: get doraHyouji to be revealed, accounting for minkan delay
# previously delayed kan-dora will always be revealed
function getNewDoraHyouji(kyoku, type) => with kyoku
  if not (rule = ..rulevar.dora.kan) then return
  lo = ..globalPublic.doraHyouji.length
  hi = ..globalPublic.nKan - (rule[type] ? 0)
  if hi < lo then return null
  return ..globalHidden.doraHyouji[lo to hi]

# master <replicate>: reveal provided doraHyouji
function addDoraHyouji(kyoku, doraHyouji)
  if doraHyouji?.length > 0
    kyoku.globalPublic.doraHyouji.push ...doraHyouji

#}}}


export Event = {}

# symbols for attaching private unserialized props on events:
KYOKU = Symbol \kyoku # ref to kyoku
FUURO = Symbol \fuuro # implicit fuuro object FIXME: use regular field

# 2 categories of event:
# master-initiated:
# - construct then apply on master (by game logic)
# - send partial info to replicates
# - reconstruct then apply on replicates
# replicate-initiated:
# - construct on replicate-me (by player decision)
# - send constructor args to master
# - construct then apply on master (`doraHyouji` might be tagged on)
# - send full info to replicates
# - reconstruct then apply on replicates
#
# Notice that "constructor args" is also a minimal set of parameters that
# sufficiently determines the event (at current kyoku state)
#
# Data fields for each event are described in the following manner:
# common:
#   "minimal": args used to construct
#   "private": cached values
# master-initiated:
#   "partial": sent to replicates (does NOT include "minimal")
# replicate-initiated:
#   "full": sent to replicates (includes "minimal")


Event.deal = class Deal #{{{
  # master-initiated
  # minimal:
  #   wall: ?[136]Pai -- defaults to randomly shuffled
  # partial:
  #   haipai: [13]Pai
  #   initDoraHyouji: [1]Pai
  # private:
  #   SPLIT: cached split wall
  SPLIT = Symbol \split

  (kyoku, @wall) -> with kyoku
    assert not ..isReplicated
    @type = \deal
    @seq = 0
    @wall ?= Pai.shuffleAll ..rulevar.dora.akahai
    @init kyoku

  init: (kyoku) -> with @[KYOKU] = kyoku
    # must be the first event
    assert.equal ..seq, 0
    assert.equal ..phase, \begin
    if not ..isReplicated # master
      assert.lengthOf @wall, 136
      @[SPLIT] = s = splitWall @wall
    else # replicate
      assert.lengthOf @haipai, 13
      assert.lengthOf @initDoraHyouji, 1
    return this

  apply: !-> with kyoku = @[KYOKU]
    if not ..isReplicated # master
      s = @[SPLIT]
      initDoraHyouji = [s.initDoraHyouji.0]
      ..globalHidden = s
      ..playerHidden = for p til 4
        new PlayerHidden s.haipai[(4 - ..chancha + p) % 4]
    else # replicate
      initDoraHyouji = @initDoraHyouji
      ..globalHidden = null
      ..playerHidden = for p til 4
        if p == ..me then new PlayerHidden @haipai
        else new PlayerHiddenMock
    addDoraHyouji(kyoku, initDoraHyouji)

    ..phase = \preTsumo
    ..seq++
#}}}

Event.tsumo = class Tsumo #{{{
  # master-initiated
  # minimal: (null)
  # partial:
  #	  player: 0/1/2/3
  #	  rinshan: bool
  #	  pai: ?Pai -- for current player only

  # constructor: master
  (kyoku) -> with kyoku
    assert not ..isReplicated
    assert ..globalPublic.nPiipaiLeft > 0
    @type = \tsumo
    @seq = ..seq
    @player = ..currPlayer
    @rinshan = ..rinshan
    if @rinshan
      @pai = ..globalHidden.rinshan[*-1]
    else
      @pai = ..globalHidden.piipai[*-1]
    @init kyoku

  init: (kyoku) -> with @[KYOKU] = kyoku
    assert.equal @seq, ..seq
    assert.equal @player, ..currPlayer
    assert.equal ..phase, \preTsumo
    return this

  apply: !-> with kyoku = @[KYOKU]
    if not ..isReplicated # master
      with ..globalHidden
        if @isRinshan
          ..rinshan.pop!
          # ..piipai.shift! # unnecessary because we check nPiipaiLeft
        else
          ..piipai.pop!
    ..globalPublic.nPiipaiLeft--
    ..playerHidden[..currPlayer].tsumo @pai

    ..currPai = @pai
    ..phase = \postTsumo
    ..seq++
#}}}

Event.dahai = class Dahai #{{{
  # replicate-initiated
  # minimal:
  #   pai: ?Pai -- null implies tsumokiri
  #   tsumokiri: ?bool
  #   riichi: bool
  # full:
  #   player: 0/1/2/3
  #   newDoraHyouji: ?[]Pai

  (kyoku, {@pai = null, @tsumokiri = false, @riichi = false}) -> with kyoku
    @type = \dahai
    @seq = ..seq
    @player = ..currPlayer
    if ..isReplicated
      assert.equal @player, ..me,
        "cannot construct for others on replicate instance"
    # null `pai` implies tsumokiri
    # by definition: `pai = tsumohai`
    if !@pai? or @tsumokiri
      @pai = ..playerHidden[@player].tsumohai
      assert.isNotNull @pai, "tsumokiri requires tsumohai"
      @tsumokiri = true
    @init kyoku

  init: (kyoku) -> with @[KYOKU] = kyoku
    assert.equal @seq, ..seq
    assert.equal @player, ..currPlayer
    assert ..phase in <[postTsumo postChiPon]>,
      "can only dahai after tsumo/chi/pon"

    PH = ..playerHidden[@player]
    PP = ..playerPublic[@player]

    if PP.riichi.accepted
      assert.isTrue @tsumokiri, "can only tsumokiri after riichi"
      assert.isFalse @riichi, "can only riichi once"

    # master: try reveal doraHyouji
    if not ..isReplicated
      @newDoraHyouji ?= getNewDoraHyouji kyoku, \dahai
    # replicate-others: no information for checking others => assume valid
    if ..isReplicated and @player != ..me then return this

    # master, replicate-me
    pai = @pai
    with (if @tsumokiri then PH.canTsumokiri! else PH.canDahai pai)
      assert ..valid, ..reason
    if @riichi
      assert.isTrue PP.menzen, "can only riichi when menzen"
      n = ..globalPublic.nPiipaiLeft
      m = ..rulevar.riichi.minPiipaiLeft
      assert n >= m, "need at least #m piipai left (only #n now)"
      if @tsumokiri
        decomp = PH.decompTenpai # maintained by PlayerHidden
      else
        decomp = PH.decompTenpaiWithout pai # calculated on demand
      assert decomp?.wait?.length > 0, "not tenpai if dahai is [#pai]"
    if ..phase == \postChiPon
      assert not ..isKuikae(PP.fuuro[*-1], pai), "kuikae banned by rule"

    return this

  apply: !-> with kyoku = @[KYOKU]
    PH = ..playerHidden[@player]
    PP = ..playerPublic[@player]

    if @riichi
      PP.riichi.declared = true
      if ..isTrueFirstTsumo @player then PP.riichi.double = true
    else
      ... # TODO: unified generalized ippatsu
    if @tsumokiri
      PH.tsumokiri!
      PP.tsumokiri @pai
    else
      PH.dahai @pai
      PP.dahai @pai

    .._updateFuritenDahai @player
    addDoraHyouji kyoku, @newDoraHyouji

    ..currPai = @pai
    ..phase = \postDahai
    ..seq++
#}}}

Event.ankan = class Ankan #{{{
  # replicate-initiated
  # minimal:
  #   pai: Pai
  # full:
  #   player: 0/1/2/3
  #   newDoraHyouji: ?[]Pai
  # private:
  #   FUURO

  (kyoku, @pai) -> with kyoku
    @type = \ankan
    @seq = ..seq
    @player = ..currPlayer
    if ..isReplicated
      assert.equal @player, ..me,
        "cannot construct for others on replicate instance"
    @init kyoku

  init: (kyoku) -> with @[KYOKU] = kyoku
    assert.equal @seq, ..seq
    assert.equal @player, ..currPlayer
    assert.equal ..phase, \postTsumo

    GP = ..globalPublic
    PH = ..playerHidden[player]

    assert.notNull @pai
    pai = @pai = @pai.equivPai

    assert GP.nPiiPaiLeft > 0, "cannot kan when no piipai left"
    if GP.nKan >= 4 # FIXME: should be redundant
      if not ..suukantsuCandidate!? then debugger

    # build fuuro object
    if pai.isSuupai and pai.number == 5
      # include all akahai
      akahai = pai.akahai
      nAkahai = ..rulevar.dora.akahai[pai.S]
      ownPai = [akahai]*nAkahai ++ [pai]*(4 - nAkahai)
    else
      ownPai = [pai]*4
    @[FUURO] = {
      type: \ankan
      pai, ownPai
      otherPai: null
      fromPlayer: null
      kakanPai: null
    }

    # replicate-others: no information for checking others => assume valid
    if ..isReplicated and @player != ..me then return this

    # master: try reveal doraHyouji
    if not ..isReplicated
      @newDoraHyouji ?= getNewDoraHyouji kyoku, \ankan

    # master, replicate-me
    assert.equal (n = PH.countEquiv pai), 4,
      "not enough [#pai] (you have #n, need 4)"
    if @playerPublic[player].riichi.accepted
      assert.isTrue @rulevar.riichi.ankan, "riichi ankan: not allowed by rule"
      # riichi ankan condition (simplified)
      #   basic: all tenpai decomps must have `pai` as koutsu
      #   okurikan: can only use tsumohai for ankan
      #
      # TODO: some impls have a more relaxed "basic" rule:
      #   tenpai/wait set must not change
      # "okurikan" rule above might still apply even with relaxed "basic"
      d = PH.decompTenpai
      allKoutsu = d.decomps.every -> it.mentsu.some ->
        it.type == \koutsu and it.pai == pai
      assert allKoutsu, "riichi ankan: hand decomposition must not change"
      if not @rulevar.riichi.okurikan
        assert.equal PH.tsumohai.equivPai, pai,
          "riichi ankan: okurikan not allowed by rule"

    return this

  apply: !-> with kyoku = @[KYOKU]
    # if ++..globalPublic.nKan > 4 then return @_checkRyoukyoku!
    # TODO: impl ryoukyoku in general -- above should be unnecessary

    ..playerHidden[@player].removeEquivN pai, 4
    ..playerPublic[@player].fuuro.push @[FUURO]

    # TODO: unified generalized ippatsu
    addDoraHyouji kyoku, @newDoraHyouji

    ..currPai = @pai
    ..phase = \postKan
    ..seq++
#}}}

Event.kakan = class Kakan #{{{
  # replicate-initiated
  # minimal:
  #   pai: Pai -- see `kakanPai` in fuuro/kakan
  # full:
  #   player: 0/1/2/3
  #   newDoraHyouji: ?[]Pai
  # private:
  #   FUURO

  (kyoku, @pai) -> with kyoku
    @type = \kakan
    @seq = ..seq
    @player = ..currPlayer
    if ..isReplicated
      assert.equal @player, ..me,
        "cannot construct for others on replicate instance"
    @init kyoku

  init: (kyoku) -> with @[KYOKU] = kyoku
    assert.equal @seq, ..seq
    assert.equal @player, ..currPlayer
    assert.equal ..phase, \postTsumo

    GP = ..globalPublic
    PH = ..playerHidden[player]
    PP = ..playerPublic[player]

    assert.notNull @pai
    {equivPai} = pai = @pai

    assert GP.nPiiPaiLeft > 0, "cannot kan when no piipai left"
    if GP.nKan >= 4 # FIXME: should be redundant
      if not ..suukantsuCandidate!? then debugger

    # find fuuro/minko object to be modified
    fuuro = PP.fuuro.find -> it.type == \minko and it.pai == equivPai
    assert.notNull fuuro, "need existing minko of [#equivPai]"
    @[FUURO] = fuuro

    # master: try reveal doraHyouji
    if not ..isReplicated
      @newDoraHyouji ?= getNewDoraHyouji kyoku, \kakan
    # <replicate-others>: no information for checking others => assume valid
    if ..isReplicated and @player != ..me then return this

    # master, replicate-me: check if `pai` exists in juntehai
    assert.equal PH.count1(pai), 1

    return this

  apply: !-> with kyoku = @[KYOKU]
    # if ++..globalPublic.nKan > 4 then return @_checkRyoukyoku!
    # TODO: impl ryoukyoku in general -- above should be unnecessary

    ..playerHidden[player].removeEquivN @pai.equivPai, 1
    @[FUURO]
      ..type = \kakan
      ..kakanPai = @pai

    # TODO: unified generalized ippatsu
    addDoraHyouji kyoku, @newDoraHyouji

    ..currPai = @pai
    ..phase = \postKan
    ..seq++
#}}}

Event.tsumoAgari = class TsumoAgari #{{{
  # replicate-initiated:
  # minimal: null
  # full:
  #   player: 0/1/2/3
  #   delta: [4]Number
  #   agari: Agari

  (kyoku) -> with kyoku
    @type = \tsumoAgari
    @seq = ..seq
    @player = ..currPlayer
    if ..isReplicated
      assert.equal @player, ..me,
        "cannot construct for others on replicate instance"
    @init kyoku

  init: (kyoku) -> with @[KYOKU] = kyoku
    assert.equal @seq, ..seq
    assert.equal @player, ..currPlayer
    assert.equal ..phase, \preTsumo

    # <replicate-others>: no information for checking others => assume valid
    if ..isReplicated and @player != ..me then return this

    # master, replicate-me
    tsumohai = ..playerHidden[player].tsumohai
    assert.notNull tsumohai, "tsumoAgari requires tsumohai"
    @agari = .._agari(player, tsumohai)
    assert.notNull @agari
    return this

  apply: !-> with kyoku = @[KYOKU]
    delta = ..globalPublic.delta
    for i til 4 => delta[i] += @agari.delta[i]
    delta[@player] += ..globalPublic.kyoutaku*1000
    .._end {
      type: \tsumoAgari
      delta
      kyoutaku: 0 # taken
      renchan: ..chancha == @player
      details: @agari
    }
#}}}

Event.kyuushuukyuuhai = class Kyuushuukyuuhai #{{{
  # replicate-initiated
  # minimal: null
  # full:
  #   player: 0/1/2/3
  #   delta: [4]Number

  (kyoku) -> with kyoku
    ...

  init: (kyoku) -> with @[KYOKU] = kyoku
    ...

  apply: !-> with kyoku = @[KYOKU]
    ...
#}}}

Event.declare = class Declare #{{{
  # replicate-initiated (partial)
  # partial:
  #   player: 0/1/2/3
  #   what: chi/pon/daiminkan/ron
  # minimal == full: (includes partial)
  #   args: (constructor args for constructing corresponding event)

  (kyoku, @player, @what, @args) -> with kyoku
    @type = \declare
    @seq = ..seq
    @init kyoku

  init: (kyoku) -> with @[KYOKU] = kyoku
    new Event[@what](kyoku) # verify validity
    return this

  apply: !-> with kyoku = @[KYOKU]
    ..lastDecl
      ..[@what] = ..[@player] = @args ? true
    ..seq++ # TODO: should we make all decls share seq?
#}}}

Event.chi = class Chi #{{{
  # replicate-declared
  # minimal:
  #   player: 0/1/2/3 -- must be next player of `currPlayer`
  #   option 1:
  #     ownPai: [2]Pai -- should satisfy the following:
  #       ownPai.0.equivNumber < ownPai.1.equivNumber
  #       `ownPai ++ kyoku.currPai` should form shuntsu
  #   option 2:
  #     dir: Number
  #       < 0 : e.g. 34m chi 5m
  #       = 0 : e.g. 46m chi 5m
  #       > 0 : e.g. 67m chi 5m
  #     preferAkahai: bool
  #       suppose you have the choice of using akahai or normal 5:
  #         true : use akahai
  #         false: use normal 5
  # full:
  #   ownPai: [2]Pai
  # private:
  #   FUURO

  (kyoku, {@player, @ownPai, dir, preferAkahai = true}) -> with kyoku
    @type = \chi
    @seq = ..seq
    if ..isReplicated
      assert.equal @player, ..me,
        "cannot construct for others on replicate instance"
    if !@ownPai?
      # infer `ownPai` from `dir`, `preferAkahai`, and player's juntehai
      assert.isNumber dir
      assert.isBoolean preferAkahai
      with ..currPai # sutehai
        n = ..equivNumber # number
        P = Pai[..S] # suite
      # properties of ownPai:
      #
      switch
      | dir <  0 => assert n not in [1 2] ; op0 = P[n - 2] ; op1 = P[n - 1]
      | dir == 0 => assert n not in [1 9] ; op0 = P[n - 1] ; op1 = P[n + 1]
      | dir >  0 => assert n not in [8 9] ; op0 = P[n + 1] ; op1 = P[n + 2]
      @ownPai = [op0, op1]
      with ..playerHidden[player]
        assert (..countEquiv op0 and ..countEquiv op1),
          "you must have [#{op0}#{op1}] in juntehai"
        # check whether we replace one of @ownPai with corresponding akahai
        if op0.number == 5 then i = 0 ; p5 = op0
        if op1.number == 5 then i = 1 ; p5 = op1
        if p5?
          p0 = p5.akahai
          p5n = ..count1 p5
          p0n = ..count1 p0
          # truth table: (has normal), (has akahai, prefer akahai) -> use akahai
          # |   | 00 | 01 | 11 | 10 |
          # | 0 | X  | X  | 1  | 1  |
          # | 1 | 0  | 0  | 1  | 0  |
          if p5n == 0 or (p0n > 0 and preferAkahai) then @ownPai[i] = p0
    @init kyoku

  init: (kyoku) -> with @[KYOKU] = kyoku
    assert.equal @seq, ..seq
    assert.equal @player, (..currPlayer + 1)%4, "can only chi from left/kamicha"
    assert.equal ..phase, \postDahai

    assert.lengthOf @ownPai, 2
    a = @ownPai.0
    b = @ownPai.1
    c = ..currPai
    assert a.N < b.N, "ownPai should be in ascending order"
    [p, q, r] = [a, b, c] .map (.equivPai) .sort Pai.compare
    assert (p.suite == q.suite == r.suite and p.succ == q and q.succ == r),
      "[#p#q#r] is not valid shuntsu"

    # build fuuro object
    @[FUURO] = {
      type: \minjun
      pai: p
      ownPai: @ownPai
      otherPai: c
      fromPlayer: ..currPlayer
      kakanPai: null
    }

    # replicate-others: no information for checking others => assume valid
    if ..isReplicated and @player != ..me then return this

    with ..playerHidden[player]
      assert (..count1 a and ..count1 b), "you must have [#a#b] in juntehai"

    return this

  apply: !-> with kyoku = @[KYOKU]
    ..playerHidden[@player].remove2 pai0, pai1
    ..playerPublic[@player]
      ..fuuro.push fuuro
      ..menzen = false
    ..playerPublic[..currPlayer].lastSutehai.fuuroPlayer = @player

    # TODO: unified generalized ippatsu

    ..currPlayer = @player
    ..phase = \turn # do not advance yet -- see `..resolveQuery`
    ..seq++
#}}}

Event.pon = class Pon #{{{
  # replicate-initiated
  # minimal: null
  # full:
  #   player: 0/1/2/3
  #   delta: [4]Number

  (kyoku) -> with kyoku
    ...

  init: (kyoku) -> with @[KYOKU] = kyoku
    ...

  apply: !-> with kyoku = @[KYOKU]
    ...
#}}}


