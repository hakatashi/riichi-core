require! {
  './pai': Pai
}

# TODO: doc the whole algorithm

export !function init
  makeDecomp1C!
  makeDecomp1W!


########################################
# packed bin
# 1 pos => 3 bits (octal)

const SEVEN = 8~777_777_777
const FOUR  = 8~444_444_444
const THREE = 8~333_333_333

export function binValid(x)
  not ( ((x.&.THREE)+(0.|.THREE)).&.x.&.FOUR )
export function binGet(x, i)
  (x.>>.((i.|.0)+(i.<<.1))).&.8~7
export function binToString(key)
  s = Number key .toString 8
  return ('0' * (9 - s.length)) + s


########################################
# complete

export decomp1C = []
made1C = false
export !function makeDecomp1C
  return if made1C
  made1C = true

  jantou = null
  shuntsu = 0
  mentsu = [0 0 0 0]
  !function dfsShuntsu(n, iMin, binOld)
    for i from iMin til 7
      bin = (binOld + (8~111.<<.((i.|.0)+(i.<<.1)))).|.0
      if binValid bin
        shuntsu++
        mentsu[n] = i
        decomp1C.[][bin].push {shuntsu, jantou, mentsu: mentsu.slice(0, n + 1)}
        if n < 3
          dfsShuntsu n + 1, i, bin
          dfsKoutsu  n + 1, 0, bin
        shuntsu--
  !function dfsKoutsu(n, iMin, binOld)
    for i from iMin til 9
      bin = (binOld + (8~3.<<.((i.|.0)+(i.<<.1)))).|.0
      if binValid bin
        mentsu[n] = i.|.2~10000
        decomp1C.[][bin].push do
          {shuntsu, jantou, mentsu: mentsu.slice(0, n + 1)}
        if n < 3
          dfsKoutsu n + 1, i, bin
  decomp1C[0] = [{shuntsu: 0, jantou: null, mentsu: []}]
  dfsShuntsu 0 0 0
  dfsKoutsu  0 0 0
  for jantou til 9
    bin = 8~2.<<.((jantou.|.0)+(jantou.<<.1))
    decomp1C[bin] = [{shuntsu, jantou, mentsu: []}]
    dfsShuntsu 0 0 bin
    dfsKoutsu  0 0 bin


########################################
# waiting

export decomp1W = []
made1W = false
export !function makeDecomp1W
  return if made1W
  made1W = true

  # NOTE: I know that stateful-ness is bad, but I could not think of a "pure"
  # way of handling `hasJantou` and `allHasShuntsu` as clean...
  for binC, cs of decomp1C
    binC = Number binC
    hasJantou = cs.0.jantou?
    nMentsu = cs.0.mentsu.length
    allHasShuntsu = cs.every (.shuntsu > 0)
    if not hasJantou
      hasJantou = true # tanki serves as jantou
      for i from 0 to 8 => expand \tanki 8~1 0 0 i
      hasJantou = false # restore it
    if nMentsu < 4
      for i from 0 to 8 => expand \shanpon 8~2 0 0 i
      allHasShuntsu = true # kanchan/ryanmen/penchan serves as shuntsu
      for i from 0 to 6 => expand \kanchan 8~101 1 0 i
      expand \penchan 8~11 2 0 0
      for i from 1 to 6
        expand \ryanmen 8~11 -1 -1 i
        expand \ryanmen 8~11 2 0 i
      expand \penchan 8~11 -1 -1 7
      # NOTE: no need to restore `allHasShuntsu`
  !function expand(tenpaiType, pat, dTenpai, dAnchor, i)
    binW = (binC + (pat.<<.((i.|.0)+(i.<<.1)))).|.0
    tenpaiN = i + dTenpai
    anchorN = i + dAnchor
    if binValid binW and binGet(binW, tenpaiN) < 4
      decomp1W.[][binW].push {
        binC, cs
        hasJantou, allHasShuntsu
        tenpaiType, tenpaiN, anchorN
      }


########################################
# kokushi-musou and chiitoitsu
# shorthand: `k`, `7`, `k7`

# kokushi tenpai: either
# - [19m19p19s1234567z] => 13-wait
# - replacing one from above with another => 1-wait (the replaced)
function tenpaiK(bins)
  yaochuu = Pai.yaochuuFromBins bins
  c0 = c1 = c2 = 0
  i0 = -1
  for x, i in yaochuu => switch x
  | 0
    if ++c0 > 1 then return null
    i0 = i
  | 1 => ++c1
  | 2
    if ++c2 > 1 then return null
  | 3, 4 => return null
  if c1 == 13
    return 13
  if c0 == 1 and c1 == 11 and c2 == 1
    return i0
  return null

# chiitoi tenpai: 6 toitsu + 1 tanki
function tenpai7(bins)
  c1 = c2 = 0
  p1 = null
  for s til 4 => for n til 9 => switch bins[s][n]
  | 0 => void
  | 1
    if ++c1 > 1 then return null
    p1 = Pai[s][n+1]
  | 2 => ++c2
  | _ => return null
  if c1 == 1 and c2 == 6 then return p1
  return null


########################################
# tenpai

mentsuWithSuite = Pai[0 1 2 3].map (P) -> (x) ->
  type: if x.&.2~10000 then \anko else \shuntsu
  anchor: P[(x.&.2~1111) + 1]

DT_KOKUSHI = Pai.YAOCHUU.map (tenpai) -> [{
  mentsu: [], jantou: null, k7: \kokushi
  tenpaiType: \kokushi, tenpai, anchor: tenpai
}]
DT_KOKUSHI13 = Pai.YAOCHUU.map (tenpai) -> {
  mentsu: [], jantou: null, k7: \kokushi
  tenpaiType: \kokushi13, tenpai, anchor: tenpai
}

export function decompTenpai(bins)
  # kokushi: exclusive
  if (w = tenpaiK bins)?
    if w == 13
    then return {
      decomps: DT_KOKUSHI13
      tenpaiSet: Pai.YAOCHUU
    }
    else return {
      decomps: DT_KOKUSHI[w]
      tenpaiSet: [Pai.YAOCHUU[w]]
    }

  decomps = []
  tenpaiSet = []

  # packed bins for table lookup
  bitBins = bins.map -> it.reduceRight (a, b) -> (a.<<.3).|.b

  # complete decomp for each suite
  # 1-7z cannot form shuntsu
  css =
    decomp1C[bitBins.0]
    decomp1C[bitBins.1]
    decomp1C[bitBins.2]
    decomp1C[bitBins.3]?.filter (.shuntsu == 0)

  # number of suites without complete decomp:
  #   0 => tenpai might come from any suite (try each)
  #   1 => tenpai must come from this suite
  #   2+ => no (non-k7) solution; fail
  jw = -1
  skip = false
  for j til 4
    if not css[j]?.length
      if jw == -1 then jw = j
      else
        skip = true
        break
  if not skip
    switch jw
    | 0 => f 0 1 2 3
    | 1 => f 1 0 2 3
    | 2 => f 2 0 1 3
    | 3 => f 3 0 1 2
    | _
      f 0 1 2 3
      f 1 0 2 3
      f 2 0 1 3
      f 3 0 1 2
  !function f(jw, j0, j1, j2)
    ws = decomp1W[bitBins[jw]]
    return unless ws?
    cs0 = css[j0]
    cs1 = css[j1]
    cs2 = css[j2]

    # filter: exactly 1 jantou from all sources
    # complete suites may only contribute 0 or 1
    cJantou0 = cs0.0.jantou
    cJantou1 = cs1.0.jantou
    cJantou2 = cs2.0.jantou
    cJantouN = cJantou0? + cJantou1? + cJantou2?
    return unless cJantouN <= 1
    # cache the jantou (if any)
    switch
    | cJantou0? => cJantou = Pai[j0][that + 1]
    | cJantou1? => cJantou = Pai[j1][that + 1]
    | cJantou2? => cJantou = Pai[j2][that + 1]
    | _ => cJantou = null

    # tenpai set, represented as a bitmap
    # e.g. jw == 0 then bit 2 set means 3m in tenpai set
    bitmap = 0

    # NOTE: despite the deeply nested (5-layer) for loops, iteration count
    # of the inner loop is small due to all the constraints on solution

    # each: tenpai suite
    for {cs: csw, tenpaiType, tenpaiN, anchorN}:w in ws
      # filter: 1-7z cannot form shuntsu
      # NOTE: not redundant; this decides if tenpai is added to set
      continue if jw == 3 and w.allHasShuntsu
      # filter: exactly 1 jantou from all sources
      # jantou either comes from complete suites or tenpai suite
      continue unless cJantouN == 1 xor w.hasJantou

      bitmap .|.= 1.<<.tenpaiN
      tenpai = Pai[jw][tenpaiN + 1]
      anchor = Pai[jw][anchorN + 1]
      # each: complete component of tenpai suite
      for cw in csw
        # filter: 1-7z cannot form shuntsu
        continue if jw == 3 and cw.shuntsu > 0
        wJantou = if cw.jantou? then Pai[jw][that + 1] else null
        # each: complete suites
        for c0 in cs0 => for c1 in cs1 => for c2 in cs2
          # NOTE: shuntsu already filtered (see `css` above)
          decomps.push {
            mentsu: [].concat do
              cw.mentsu.map mentsuWithSuite[jw]
              c0.mentsu.map mentsuWithSuite[j0]
              c1.mentsu.map mentsuWithSuite[j1]
              c2.mentsu.map mentsuWithSuite[j2]
            jantou: cJantou ? wJantou
            k7: null
            tenpaiType, tenpai, anchor
          }
        #end for c0, c1, c2
      #end for cw
    #end for w

    # add to overall tenpai set
    [].push.apply tenpaiSet, Pai.arrayFromBitmapSuite(bitmap, jw)
  #end function f

  # chiitoi: non-exclusive (might also be ryanpeikou)
  #
  # NOTE:
  #
  # - although chiitoi implies tanki, it does not fit in the standard decomp
  #   model and is therefore not counted as either tanki or jantou
  # - reason this is considered last: easier de-dupe in `tenpaiSet`
  #
  # (FIXME: explain this better)
  if (w = tenpai7 bins)?
    decomps.push {
      mentsu: [], jantou: null, k7: \chiitoi
      tenpaiType: \chiitoi, tenpai: w, anchor: w
    }
    if w not in tenpaiSet then tenpaiSet.push w

  tenpaiSet.sort Pai.compare
  return {decomps, tenpaiSet}


########################################
# agari

export function decompAgari({decomps}:tenpaiDecomp, agariPai, isRon)
  agariPai .= equivPai
  for {mentsu, jantou, k7, tenpaiType, tenpai, anchor} in decomps
    continue if agariPai != tenpai
    if !k7?
      switch tenpaiType
      | \tanki
        jantou = tenpai
      | \shanpon
        mentsu ++= {anchor, type: if isRon then \minko else \anko}
      | \kanchan, \penchan, \ryanmen
        mentsu ++= {anchor, type: \shuntsu}
      | _ => throw Error 'WTF'
    {mentsu, jantou, k7, tenpaiType}
