# Minimal bash assertion helpers. Source after defining the code under test.
EC_TPASS=0; EC_TFAIL=0
assert_eq() { # $1=desc $2=expected $3=actual
  if [ "$2" = "$3" ]; then EC_TPASS=$((EC_TPASS+1));
  else EC_TFAIL=$((EC_TFAIL+1)); printf 'FAIL - %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
assert_rc() { # $1=desc $2=expected_rc $3=actual_rc
  if [ "$2" = "$3" ]; then EC_TPASS=$((EC_TPASS+1));
  else EC_TFAIL=$((EC_TFAIL+1)); printf 'FAIL - %s\n  expected rc:%s actual rc:%s\n' "$1" "$2" "$3"; fi
}
ec_tests_done() { printf '%s: %d passed, %d failed\n' "${0##*/}" "$EC_TPASS" "$EC_TFAIL"; [ "$EC_TFAIL" -eq 0 ]; }
