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

st.set_page_config(page_title="Predicciones -- CRM/Billing/Universidad", page_icon="[*]")
st.title("Predicciones en vivo")
st.caption("Stretch goal: interfaz sobre los modelos entrenados en notebooks/ml/. No reemplaza el pipeline de datos.")


@st.cache_resource
def load_artifact(filename: str):
    path = MODELS_ROOT / filename
    if not path.exists():
        return None
    return joblib.load(path)


def render_form(artifact: dict, key_prefix: str) -> pd.DataFrame:
    values = {}
    for col in artifact["categorical"]:
        options = artifact["feature_options"][col]
        values[col] = st.selectbox(col, options, key=f"{key_prefix}_{col}")
    for col in artifact["numeric"]:
        lo, hi = artifact["numeric_ranges"][col]
        default = (lo + hi) / 2
        values[col] = st.slider(col, min_value=float(lo), max_value=float(hi), value=float(default), key=f"{key_prefix}_{col}")
    return pd.DataFrame([values])


tab_churn, tab_win = st.tabs(["Predecir churn", "Predecir cierre de oportunidad"])

with tab_churn:
    st.subheader("Probabilidad de cancelacion de una suscripcion")
    artifact = load_artifact("churn_model.joblib")
    if artifact is None:
        st.warning("No se encontro models/churn_model.joblib. Corre notebooks/ml/01_churn_model.ipynb primero.")
    else:
        st.caption(f"Modelo entrenado -- ROC-AUC: {artifact['metrics']['roc_auc']:.3f}")
        row = render_form(artifact, "churn")
        if st.button("Predecir churn"):
            proba = artifact["pipeline"].predict_proba(row)[0, 1]
            st.metric("Probabilidad de cancelar", f"{proba * 100:.1f}%")
            if proba >= 0.5:
                st.error("Riesgo alto de cancelacion.")
            elif proba >= 0.3:
                st.warning("Riesgo moderado.")
            else:
                st.success("Riesgo bajo.")

with tab_win:
    st.subheader("Probabilidad de cierre ganado de una oportunidad")
    artifact = load_artifact("win_model.joblib")
    if artifact is None:
        st.warning("No se encontro models/win_model.joblib. Corre notebooks/ml/02_win_model.ipynb primero.")
    else:
        st.caption(f"Modelo entrenado -- ROC-AUC: {artifact['metrics']['roc_auc']:.3f}")
        row = render_form(artifact, "win")
        if st.button("Predecir cierre"):
            proba = artifact["pipeline"].predict_proba(row)[0, 1]
            st.metric("Probabilidad de ganar el trato", f"{proba * 100:.1f}%")
            if proba >= 0.6:
                st.success("Alta probabilidad de cierre ganado.")
            elif proba >= 0.35:
                st.warning("Probabilidad media -- requiere seguimiento.")
            else:
                st.error("Baja probabilidad de cierre ganado.")
