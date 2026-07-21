"""Interfaz de prediccion en vivo para los modelos entrenados en notebooks/ml/.

App independiente del pipeline de datos -- no toca Postgres, solo carga los
.joblib ya persistidos (pipeline + opciones validas de features + metricas)
y corre predict_proba() con lo que ingresa el usuario en el formulario.
"""
import os
from pathlib import Path

import joblib
import pandas as pd
import streamlit as st

MODELS_ROOT = Path(os.environ.get("MODELS_ROOT", "/app/models"))

st.set_page_config(page_title="Predicciones -- CRM/Billing/Universidad", page_icon="🔮", layout="wide")
st.title("🔮 Predicciones en vivo")
st.caption("Stretch goal: interfaz sobre los modelos entrenados en notebooks/ml/. No reemplaza el pipeline de datos.")


@st.cache_resource
def load_artifact(filename: str):
    path = MODELS_ROOT / filename
    if not path.exists():
        return None
    return joblib.load(path)


def render_form(artifact: dict, key_prefix: str) -> pd.DataFrame:
    values = {}
    col_cat, col_num = st.columns(2)
    with col_cat:
        st.markdown("**Atributos**")
        for col in artifact["categorical"]:
            options = artifact["feature_options"][col]
            values[col] = st.selectbox(col, options, key=f"{key_prefix}_{col}")
    with col_num:
        st.markdown("**Valores**")
        for col in artifact["numeric"]:
            lo, hi = artifact["numeric_ranges"][col]
            default = (lo + hi) / 2
            values[col] = st.slider(col, min_value=float(lo), max_value=float(hi), value=float(default), key=f"{key_prefix}_{col}")
    return pd.DataFrame([values])


def render_result(proba: float, label: str, high: float, high_msg: str, mid: float, mid_msg: str, low_msg: str):
    col_metric, col_bar = st.columns([1, 2])
    with col_metric:
        st.metric(label, f"{proba * 100:.1f}%")
    with col_bar:
        st.write("")
        st.progress(proba)
    if proba >= high:
        st.error(f"⚠️ {high_msg}")
    elif proba >= mid:
        st.warning(f"◐ {mid_msg}")
    else:
        st.success(f"✅ {low_msg}")


def render_model_tab(model_file: str, notebook: str, subtitle: str, button_label: str, result_label: str, thresholds: dict, key_prefix: str):
    st.subheader(subtitle)
    artifact = load_artifact(model_file)
    if artifact is None:
        st.warning(f"No se encontro models/{model_file}. Corre {notebook} primero.")
        return

    with st.container(border=True):
        auc = artifact["metrics"]["roc_auc"]
        st.caption(f"Modelo entrenado -- ROC-AUC: {auc:.3f} (0.5 = sin señal predictiva real; ver docs/decisiones.md #15)")
        row = render_form(artifact, key_prefix)
        if st.button(button_label, key=f"{key_prefix}_btn", type="primary", use_container_width=True):
            proba = artifact["pipeline"].predict_proba(row)[0, 1]
            render_result(proba, result_label, **thresholds)


tab_churn, tab_win = st.tabs(["📉 Predecir churn", "🤝 Predecir cierre de oportunidad"])

with tab_churn:
    render_model_tab(
        model_file="churn_model.joblib",
        notebook="notebooks/ml/01_churn_model.ipynb",
        subtitle="Probabilidad de cancelacion de una suscripcion",
        button_label="Predecir churn",
        result_label="Probabilidad de cancelar",
        thresholds={
            "high": 0.5, "high_msg": "Riesgo alto de cancelacion.",
            "mid": 0.3, "mid_msg": "Riesgo moderado.",
            "low_msg": "Riesgo bajo.",
        },
        key_prefix="churn",
    )

with tab_win:
    render_model_tab(
        model_file="win_model.joblib",
        notebook="notebooks/ml/02_win_model.ipynb",
        subtitle="Probabilidad de cierre ganado de una oportunidad",
        button_label="Predecir cierre",
        result_label="Probabilidad de ganar el trato",
        thresholds={
            "high": 0.6, "high_msg": "Alta probabilidad de cierre ganado.",
            "mid": 0.35, "mid_msg": "Probabilidad media -- requiere seguimiento.",
            "low_msg": "Baja probabilidad de cierre ganado.",
        },
        key_prefix="win",
    )
