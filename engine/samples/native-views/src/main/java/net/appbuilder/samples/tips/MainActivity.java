package net.appbuilder.samples.tips;

import android.content.SharedPreferences;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;

import net.appbuilder.samples.tips.databinding.ActivityMainBinding;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.NumberFormat;
import java.util.Locale;

public class MainActivity extends AppCompatActivity {
    private static final String PREFS = "tips";
    private ActivityMainBinding binding;
    private SharedPreferences prefs;
    private final NumberFormat money = NumberFormat.getCurrencyInstance(Locale.getDefault());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());
        ViewCompat.setOnApplyWindowInsetsListener(binding.root, (view, insets) -> {
            Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.ime());
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsetsCompat.CONSUMED;
        });

        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        binding.tipSlider.setValue(prefs.getInt("tip", 10));
        binding.tipSlider.addOnChangeListener((slider, value, fromUser) -> {
            prefs.edit().putInt("tip", (int) value).apply();
            recalculate();
        });
        TextWatcher watcher = new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
            }

            @Override
            public void afterTextChanged(Editable s) {
                recalculate();
            }
        };
        binding.bill.addTextChangedListener(watcher);
        binding.people.addTextChangedListener(watcher);
        recalculate();
    }

    private void recalculate() {
        int tipPercent = (int) binding.tipSlider.getValue();
        binding.tipLabel.setText(getString(R.string.tip_label, tipPercent));
        BigDecimal bill = parse(String.valueOf(binding.bill.getText()));
        int people = Math.max(1, (int) parse(String.valueOf(binding.people.getText())).longValue());
        if (bill.signum() <= 0) {
            binding.result.setText(R.string.result_empty);
            return;
        }
        BigDecimal tip = bill.multiply(BigDecimal.valueOf(tipPercent)).divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
        BigDecimal total = bill.add(tip);
        BigDecimal perPerson = total.divide(BigDecimal.valueOf(people), 2, RoundingMode.HALF_UP);
        binding.result.setText(getString(R.string.result_template, money.format(tip), money.format(total), money.format(perPerson)));
    }

    private static BigDecimal parse(String text) {
        try {
            return new BigDecimal(text.trim().replace(',', '.'));
        } catch (NumberFormatException e) {
            return BigDecimal.ZERO;
        }
    }
}
