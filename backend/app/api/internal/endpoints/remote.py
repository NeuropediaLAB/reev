"""Reverse proxies to external/remote services."""

import json

import httpx
from fastapi import APIRouter, BackgroundTasks, Request, Response
from fastapi.responses import JSONResponse, StreamingResponse
from starlette.background import BackgroundTask

#: Keys for the ACMG rating
ACMG_RATING_KEYS: tuple[str, ...] = (
    "pvs1",
    "ps1",
    "ps2",
    "ps3",
    "ps4",
    "pm1",
    "pm2",
    "pm3",
    "pm4",
    "pm5",
    "pm6",
    "pp1",
    "pp2",
    "pp3",
    "pp4",
    "pp5",
    "ba1",
    "bs1",
    "bs2",
    "bs3",
    "bs4",
    "bp1",
    "bp2",
    "bp3",
    "bp4",
    "bp5",
    "bp6",
    "bp7",
)


def default_acmg_rating() -> dict[str, bool]:
    return {k: False for k in ACMG_RATING_KEYS}


router = APIRouter()


class HTTPXClientWrapper:
    """Wrapper around HTTPX AsyncClient to for graceful startup/shutdown within FastAPI."""

    transport: httpx.AsyncHTTPTransport | None = None
    async_client: httpx.AsyncClient | None = None

    def start(self):
        self.transport = httpx.AsyncHTTPTransport(retries=1)
        self.transport._pool._ssl_context.options |= 0x4  # OP_LEGACY_SERVER_CONNECT
        self.async_client = httpx.AsyncClient(timeout=httpx.Timeout(60.0), transport=self.transport)

    async def stop(self):
        await self.async_client.aclose()
        self.async_client = None

    def __call__(self):
        assert self.async_client is not None
        return self.async_client


httpx_client_wrapper = HTTPXClientWrapper()


@router.get("/variantvalidator/{path:path}")
async def variantvalidator(request: Request, path: str):
    """
    Implement VariantValidator API. Proxy requests to the
    `VariantValidator <https://rest.variantvalidator.org/>`_ backend.

    :param request: request
    :type request: :class:`fastapi.Request`
    :param path: path to append to the backend URL
    :type path: str
    :return: response
    :rtype: :class:`fastapi.responses.StreamingResponse`
    """
    url = request.url

    # change grch to GRCh and strip "chr" prefixes
    path = path.replace("grch", "GRCh").replace("chr", "")
    backend_url = "https://rest.variantvalidator.org/VariantValidator/variantvalidator/" + path

    backend_url = backend_url + (f"?{url.query}" if url.query else "")
    client = httpx_client_wrapper()
    backend_req = client.build_request(
        method=request.method,
        url=backend_url,
        content=await request.body(),
    )
    backend_resp = await client.send(backend_req, stream=True)
    return StreamingResponse(
        backend_resp.aiter_raw(),
        status_code=backend_resp.status_code,
        headers=backend_resp.headers,
        background=BackgroundTasks([BackgroundTask(backend_resp.aclose)]),
    )


def _genome_build_to_acmg(build: str) -> str:
    """Map WinterVar build names ('hg19'/'hg38') to auto-acmg genome release ('GRCh37'/'GRCh38')."""
    return "GRCh37" if build.lower() in ("hg19", "grch37") else "GRCh38"


def _genome_build_to_gnomad(build: str) -> str:
    """Map WinterVar build names to auto-acmg gnomAD-style prefix ('GRCh37'/'GRCh38')."""
    return "GRCh37" if build.lower() in ("hg19", "grch37") else "GRCh38"


async def _call_auto_acmg(
    client: httpx.AsyncClient,
    chromosome: str,
    position: str,
    reference: str,
    alternative: str,
    build: str,
) -> dict[str, bool] | None:
    """Call the local auto-acmg service and return an ACMG rating dict, or None on failure.

    Uses gnomAD-style variant_name (e.g. 'grch37-4-113568536-G-GA') which auto-acmg
    resolves directly from coordinates without calling dotty.
    """
    genome_release = _genome_build_to_acmg(build)
    gnomad_prefix = _genome_build_to_gnomad(build)
    variant_name = f"{gnomad_prefix}-{chromosome}-{position}-{reference}-{alternative}"
    url = (
        f"http://auto-acmg:8080/api/v1/predict/seqvar"
        f"?variant_name={variant_name}&genome_release={genome_release}"
    )
    try:
        resp = await client.get(url, timeout=httpx.Timeout(120.0))
        if resp.is_error:
            return None
        data = resp.json()
        criteria = data.get("prediction", {}).get("criteria", {})
        rating = default_acmg_rating()
        for key in rating:
            crit = criteria.get(key, {})
            rating[key] = crit.get("prediction") == "applicable"
        return rating
    except Exception:
        return None


async def _call_auto_acmg_strucvar(
    client: httpx.AsyncClient,
    sv_type: str,
    chromosome: str,
    start: str,
    end: str,
    genome_release: str,
) -> dict | None:
    """Call the local auto-acmg service for structural variant (CNV) prediction.

    Formats the variant name as 'DEL:chrX:start:end' (colon-separated) which
    auto-acmg resolves via its StrucVarResolver.

    Returns the full prediction dict (with 'prediction' key) or None on failure.
    """
    gr = _genome_build_to_acmg(genome_release)
    # auto-acmg accepts DEL/DUP prefix with colon-separated coordinates
    sv_type_upper = sv_type.upper()  # DEL or DUP
    variant_name = f"{sv_type_upper}:chr{chromosome}:{start}:{end}"
    url = (
        f"http://auto-acmg:8080/api/v1/predict/strucvar"
        f"?variant_name={variant_name}&genome_release={gr}"
    )
    try:
        resp = await client.get(url, timeout=httpx.Timeout(180.0))
        if resp.is_error:
            return None
        return resp.json()
    except Exception:
        return None


@router.get("/acmg/{path:path}")
async def acmg(request: Request):
    """
    Implement searching for ACMG classification for SNVs and indels.

    Tries the local auto-acmg service first (supports all variant types).
    Falls back to the `WinterVar <http://wintervar.wglab.org/>`_ external API
    (missense SNVs only) if auto-acmg is unavailable.

    :param request: request
    :type request: :class:`fastapi.Request`
    :return: ACMG classification
    :rtype: dict
    """
    query_params = request.query_params
    chromosome = query_params.get("chromosome")
    position = query_params.get("position")
    reference = query_params.get("reference")
    alternative = query_params.get("alternative")
    build = query_params.get("release")

    if not chromosome or not position or not reference or not alternative or not build:
        return Response(status_code=400, content="Missing query parameters")

    client = httpx_client_wrapper()

    # Try auto-acmg first (handles all variant types: SNVs, indels, etc.)
    auto_acmg_rating = await _call_auto_acmg(client, chromosome, position, reference, alternative, build)
    if auto_acmg_rating is not None:
        return JSONResponse(auto_acmg_rating)

    # Fall back to WinterVar (missense SNVs only)
    url = (
        f"http://wintervar.wglab.org/api_new.php?"
        f"queryType=position&chr={chromosome}&pos={position}"
        f"&ref={reference}&alt={alternative}&build={build}"
    )
    backend_req = client.build_request(method="GET", url=url)
    backend_resp = await client.send(backend_req)
    if backend_resp.is_error:
        return Response(status_code=backend_resp.status_code, content=backend_resp.content)

    try:
        backend_json = backend_resp.json()
    except json.JSONDecodeError:
        # WinterVar returns plain text for unsupported variant types (e.g. insertions).
        # Return a default (all-False) rating so the frontend shows "no prediction".
        return JSONResponse(default_acmg_rating())

    acmg_rating = default_acmg_rating()
    for key, value in backend_json.items():
        if key.lower() in acmg_rating:
            acmg_rating[key.lower()] = value == 1
    return JSONResponse(acmg_rating)


@router.get("/acmg-strucvar/")
async def acmg_strucvar(request: Request):
    """
    Return auto-acmg structural variant (CNV) ACMG criteria prediction.

    Uses the local auto-acmg service (/api/v1/predict/strucvar) to evaluate
    deletions and duplications according to ACMG/ClinGen SV guidelines.

    Query params: sv_type (DEL|DUP), chromosome, start, end, genome_release
    """
    query_params = request.query_params
    sv_type = query_params.get("sv_type")
    chromosome = query_params.get("chromosome")
    start = query_params.get("start")
    end = query_params.get("end")
    genome_release = query_params.get("genome_release", "GRCh38")

    if not sv_type or not chromosome or not start or not end:
        return Response(status_code=400, content="Missing query parameters (sv_type, chromosome, start, end required)")

    client = httpx_client_wrapper()
    result = await _call_auto_acmg_strucvar(client, sv_type, chromosome, start, end, genome_release)
    if result is None:
        return Response(status_code=502, content="auto-acmg strucvar prediction unavailable")
    return JSONResponse(result)


@router.get("/cnv/acmg/{path:path}")
async def cnv_acmg(request: Request):
    """
    Implement searching for ACMG classification for CNVs.
    Proxy requests to the `wAutoCNV <https://phoenix.bgi.com/>`_ backend.

    :param request: request
    :type request: :class:`fastapi.Request`
    :return: ACMG classification
    :rtype: dict
    """
    query_params = request.query_params
    chromosome = query_params.get("chromosome")
    start = query_params.get("start")
    end = query_params.get("end")
    func = query_params.get("func")

    if not chromosome or not start or not end or not func:
        return Response(status_code=400, content="Missing query parameters")

    client = httpx_client_wrapper()
    backend_req = client.build_request(
        method="POST",
        url="https://phoenix.bgi.com/api/acit/jobs/",
        data={"chromosome": chromosome, "start": start, "end": end, "func": func, "error": 0},
    )
    backend_resp = await client.send(backend_req)
    if backend_resp.is_error:
        return Response(status_code=backend_resp.status_code, content=backend_resp.content)
    else:
        return JSONResponse(backend_resp.json())


@router.get("/pubtator3-api/{path:path}")
async def pubtator3_api(request: Request, path: str):
    """
    Proxy requests to the `PubTator 3 <https://www.ncbi.nlm.nih.gov/research/pubtator3-api/>`_ backend.

    :param request: request
    :type request: :class:`fastapi.Request`
    :param path: path to append to the backend URL
    :type path: str
    :return: response
    :rtype: :class:`fastapi.responses.StreamingResponse`
    """
    url = request.url
    backend_url = "https://www.ncbi.nlm.nih.gov/research/pubtator3-api/" + path
    backend_url = backend_url + (f"?{url.query}" if url.query else "")

    client = httpx_client_wrapper()
    backend_req = client.build_request(
        method=request.method,
        url=backend_url,
        content=await request.body(),
    )
    backend_resp = await client.send(backend_req, stream=True)
    if "set-cookie" in backend_resp.headers:
        backend_resp.headers.pop("set-cookie")
    return StreamingResponse(
        backend_resp.aiter_raw(),
        status_code=backend_resp.status_code,
        headers=backend_resp.headers,
        background=BackgroundTasks([BackgroundTask(backend_resp.aclose)]),
    )
