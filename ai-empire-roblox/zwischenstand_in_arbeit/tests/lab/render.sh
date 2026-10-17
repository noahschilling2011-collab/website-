#!/usr/bin/env bash
# Lab package previews (guiprev, approximate renders of the real UI tree): every Model Studio screen at
# 844x390 (iPhone landscape, @2x) and 1280x720 -> out/lab/{phone,desktop}_*.png
# Usage: tests/lab/render.sh [only-pattern]
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
python3 harness/make_manifest.py --src work/src --gen harness/.gen_labprev >/dev/null || exit 1
OUT=out/lab; mkdir -p "$OUT"
HQ="size=s7b focus=coding recipe=deep line=developers name=Sage"
RICH="size=s1b focus=coding recipe=steady line=developers name=Sage"
shots=(
  "01_lab_home_garage|fresh|view=home"
  "02_lab_home_hq|hq|view=home"
  "03_garage_step1_product|starter|view=design step=1"
  "04_garage_step2_size_locked|starter|view=design step=2"
  "05_garage_step3_focus|starter|view=design step=3"
  "06_garage_step4_plan|starter|view=design step=4"
  "07_garage_step5_name|starter|view=design step=5"
  "08_garage_review_first_model_buy_data|fresh|view=design"
  "09_garage_review_first_model_ready|starter|view=design"
  "10_hq_step1_product|hq|view=design step=1 $HQ"
  "11_hq_step2_size|hq|view=design step=2 $HQ"
  "12_hq_step3_focus|hq|view=design step=3 $HQ"
  "13_hq_step4_plan|hq|view=design step=4 $HQ"
  "14_hq_step5_name|hq|view=design step=5 $HQ"
  "15_hq_step6_review|hq|view=design step=6 $HQ"
  "16_rich_review_breakdown|rich|view=design step=6 breakdown=1 $RICH"
  "17_training|rich|view=training"
  "18_training_decision|rich|view=training event=1"
  "19_reveal_record|rich|view=reveal wait=3"
  "20_reveal_first_model|starter|view=reveal"
  "21_launch_day_line|rich|view=launch ls=1"
  "22_launch_day_price|rich|view=launch ls=2"
  "23_launch_day_campaign|rich|view=launch ls=3"
  "24_now_live_successor|rich|view=live"
  "25_market_chat|rich|view=market"
  "26_suggested_review_buy_plan|full|view=suggest scale=0.25"
  "27_design_reveal_ready_banner|rich|view=banner step=3 $RICH"
)
# extra viewports: a big desktop (the regular card grows with the preview zone) and a small phone (iPhone SE/8
# landscape 667x375, documented limit: the Studio scale drops to 0.532 there)
viewports=(
  "hd|1920x1080|58,0,0,0|1|15_hq_step6_review|hq|view=design step=6 $HQ"
  "se|667x375|58,0,0,0|2|15_hq_step6_review|hq|view=design step=6 $HQ"
  "se|667x375|58,0,0,0|2|06_garage_step4_plan|starter|view=design step=4"
)
for shot in "${shots[@]}"; do
  IFS='|' read -r name state extra <<< "$shot"
  if [ -n "${1:-}" ] && [[ "$name" != *$1* ]]; then continue; fi
  for vp in phone desktop; do
    dpr=1; [ "$vp" = phone ] && dpr=2
    strip=(); [[ "$name" == *market* ]] && strip=(--strip ScrollingFrame)
    python3 tools/guiprev/guiprev.py --scene tests/lab/scene_lab.luau --gen harness/.gen_labprev --no-manifest --state "$state" \
      --viewport $vp --dpr $dpr --out "$OUT/${vp}_${name}.png" "${strip[@]}" $extra >/dev/null 2>"$OUT/.err_${vp}_${name}.txt" \
      && echo "ok   ${vp}_${name}" || { echo "FAIL ${vp}_${name}"; tail -5 "$OUT/.err_${vp}_${name}.txt"; }
  done
done
for e in "${viewports[@]}"; do
  IFS='|' read -r tag vp ins dpr name state rest <<< "$e"
  if [ -n "${1:-}" ] && [[ "$name" != *$1* ]] && [[ "$tag" != *$1* ]]; then continue; fi
  python3 tools/guiprev/guiprev.py --scene tests/lab/scene_lab.luau --gen harness/.gen_labprev --no-manifest --state "$state" \
    --viewport "$vp" --insets "$ins" --dpr "$dpr" --out "$OUT/${tag}_${name}.png" $rest >/dev/null 2>"$OUT/.err_${tag}_${name}.txt" \
    && echo "ok   ${tag}_${name}" || { echo "FAIL ${tag}_${name}"; tail -5 "$OUT/.err_${tag}_${name}.txt"; }
done
