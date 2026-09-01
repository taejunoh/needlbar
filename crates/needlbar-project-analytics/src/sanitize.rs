use crate::model::UsageAggregate;
use tokscale_core::TokenBreakdown;

#[derive(Clone, Default)]
pub(crate) struct Totals {
    pub tokens: TokenBreakdown,
    pub cost: f64,
    pub cost_partial: bool,
}

impl Totals {
    pub(crate) fn add(&mut self, tokens: &TokenBreakdown, cost: f64) {
        self.tokens.input = self.tokens.input.saturating_add(nonnegative(tokens.input));
        self.tokens.output = self
            .tokens
            .output
            .saturating_add(nonnegative(tokens.output));
        self.tokens.cache_read = self
            .tokens
            .cache_read
            .saturating_add(nonnegative(tokens.cache_read));
        self.tokens.cache_write = self
            .tokens
            .cache_write
            .saturating_add(nonnegative(tokens.cache_write));
        self.tokens.reasoning = self
            .tokens
            .reasoning
            .saturating_add(nonnegative(tokens.reasoning));
        if cost.is_finite() && cost >= 0.0 {
            let candidate = self.cost + cost;
            if candidate.is_finite() {
                self.cost = candidate;
            } else {
                self.cost_partial = true;
            }
        }
    }
    pub(crate) fn dto(&self) -> UsageAggregate {
        let total = self.tokens.total().max(0);
        UsageAggregate {
            input_tokens: self.tokens.input.max(0).to_string(),
            output_tokens: self.tokens.output.max(0).to_string(),
            cache_read_tokens: self.tokens.cache_read.max(0).to_string(),
            cache_write_tokens: self.tokens.cache_write.max(0).to_string(),
            reasoning_tokens: self.tokens.reasoning.max(0).to_string(),
            total_tokens: total.to_string(),
            estimated_cost_usd: decimal(self.cost),
        }
    }
}
fn nonnegative(value: i64) -> i64 {
    value.max(0)
}

pub(crate) fn decimal(value: f64) -> String {
    if !value.is_finite() || value <= 0.0 {
        return "0".into();
    }
    let mut text = value.to_string();
    if let Some((mantissa, exponent)) = text.split_once(['e', 'E']) {
        let exponent = exponent.parse::<i32>().unwrap_or_default();
        let digits = mantissa.replace('.', "");
        let point = mantissa.find('.').unwrap_or(mantissa.len()) as i32 + exponent;
        text = if point <= 0 {
            format!("0.{}{}", "0".repeat((-point) as usize), digits)
        } else if point as usize >= digits.len() {
            format!("{}{}", digits, "0".repeat(point as usize - digits.len()))
        } else {
            format!(
                "{}.{}",
                &digits[..point as usize],
                &digits[point as usize..]
            )
        };
    }
    while text.contains('.') && text.ends_with('0') {
        text.pop();
    }
    if text.ends_with('.') {
        text.pop();
    }
    text
}

pub(crate) fn label(root: &str, id: &str) -> String {
    let candidate = root.rsplit('/').next().unwrap_or_default();
    if !candidate.is_empty() && candidate.len() <= 80 && !candidate.chars().any(char::is_control) {
        candidate.to_owned()
    } else {
        format!("Repository {}", &id[..id.len().min(8)])
    }
}
pub(crate) fn model(value: &str) -> String {
    if !value.is_empty()
        && value.len() <= 80
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | ':'))
    {
        value.to_owned()
    } else {
        "Other model".into()
    }
}
pub(crate) fn short_oid(value: &str) -> Option<String> {
    if value.len() >= 12 && value.bytes().all(|c| c.is_ascii_hexdigit()) {
        Some(value[..12].to_ascii_lowercase())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::{decimal, Totals};
    use tokscale_core::TokenBreakdown;
    #[test]
    fn tiny_positive_cost_is_canonical_without_an_exponent() {
        assert_eq!(decimal(1e-15), "0.000000000000001");
    }
    #[test]
    fn checked_cost_addition_keeps_finite_subtotal_on_overflow() {
        let mut totals = Totals::default();
        totals.add(&TokenBreakdown::default(), f64::MAX);
        totals.add(&TokenBreakdown::default(), f64::MAX);
        assert_ne!(totals.dto().estimated_cost_usd, "0");
    }
}
