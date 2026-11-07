// ============================================================================
// UNIT: uDanfeNFe
// OBJETIVO: a partir do XML da NF-e gravado pelo SAT (NF.NFEXML), gerar o
// PDF da DANFE e ler os dados da nota - usados pelo botao "Enviar NF" da
// tela de pedidos (04/11/2026).
//
// Usa o ACBr (TACBrNFe + TACBrNFeDANFeFPDF), criado aqui em tempo de
// execucao. NAO usa a DMNF do SAT de proposito: ela e' unit compartilhada do
// ERP e traz junto certificado, impressoras, NFC-e, MDF-e e NFS-e. Gerar a
// DANFE de uma nota ja autorizada nao precisa de certificado nem de acesso a
// SEFAZ.
//
// {DECISAO - 04/11/2026} DANFE pelo FPDF do ACBr, NAO pelo Fortes
// (TACBrNFeDANFeRL, o que o SAT usa): no teste com NF-e real do banco o
// Fortes falhou com "Range check error" na preparacao do relatorio, e o
// FPDF gerou a DANFE completa (chave, codigo de barras, protocolo, itens e
// impostos). O FPDF tambem gera direto em memoria, sem depender de
// impressora nem de pasta temporaria.
// ============================================================================
unit uDanfeNFe;

interface

uses
  System.SysUtils;

type
  TDadosNotaFiscal = record
    Numero: string;
    Serie: string;
    Chave: string;            // 44 digitos
    DataEmissao: TDateTime;
    ValorTotal: Double;       // vNF
    ValorProdutos: Double;    // vProd
    CFOP: string;             // CFOP do primeiro item
  end;

// Le os dados principais da nota direto do XML.
function LerDadosDoXMLNFe(const AXML: string; out ADados: TDadosNotaFiscal;
  out AErro: string): Boolean;

// Gera o PDF da DANFE em memoria e devolve os bytes.
function GerarPDFDanfe(const AXML: string; out APdf: TBytes;
  out AErro: string): Boolean;

implementation

uses
  System.Classes, ACBrNFe, ACBrNFe.Classes, ACBrNFeDANFeFPDF;

function CriarACBrComXML(const AXML: string): TACBrNFe;
begin
  Result := TACBrNFe.Create(nil);
  try
    Result.NotasFiscais.LoadFromString(AXML);
    if Result.NotasFiscais.Count = 0 then
      raise Exception.Create('XML da nota fiscal sem NF-e.');
  except
    Result.Free;
    raise;
  end;
end;

function LerDadosDoXMLNFe(const AXML: string; out ADados: TDadosNotaFiscal;
  out AErro: string): Boolean;
var
  ACBr: TACBrNFe;
  Nota: TNFe;
begin
  Result := False;
  AErro := '';
  ADados := Default(TDadosNotaFiscal);
  if Trim(AXML) = '' then
  begin
    AErro := 'A nota fiscal nao tem XML gravado no SAT.';
    Exit;
  end;
  try
    ACBr := CriarACBrComXML(AXML);
    try
      Nota := ACBr.NotasFiscais[0].NFe;
      ADados.Numero := IntToStr(Nota.Ide.nNF);
      ADados.Serie := IntToStr(Nota.Ide.serie);
      ADados.Chave := StringReplace(Nota.infNFe.ID, 'NFe', '', [rfIgnoreCase]);
      // Na NF-e 4.00 o dEmi do ACBr guarda o dhEmi (data e hora).
      ADados.DataEmissao := Nota.Ide.dEmi;
      ADados.ValorTotal := Nota.Total.ICMSTot.vNF;
      ADados.ValorProdutos := Nota.Total.ICMSTot.vProd;
      if Nota.Det.Count > 0 then
        ADados.CFOP := Nota.Det[0].Prod.CFOP;
      Result := True;
    finally
      ACBr.Free;
    end;
  except
    on E: Exception do
      AErro := 'Nao foi possivel ler o XML da nota fiscal: ' + E.Message;
  end;
end;

function GerarPDFDanfe(const AXML: string; out APdf: TBytes;
  out AErro: string): Boolean;
var
  ACBr: TACBrNFe;
  Danfe: TACBrNFeDANFeFPDF;
  Stream: TMemoryStream;
begin
  Result := False;
  AErro := '';
  SetLength(APdf, 0);
  if Trim(AXML) = '' then
  begin
    AErro := 'A nota fiscal nao tem XML gravado no SAT.';
    Exit;
  end;
  try
    ACBr := CriarACBrComXML(AXML);
    try
      Danfe := TACBrNFeDANFeFPDF.Create(nil);
      Stream := TMemoryStream.Create;
      try
        Danfe.ACBrNFe := ACBr;
        Danfe.ImprimirDANFEPDF(Stream, ACBr.NotasFiscais[0].NFe);
        SetLength(APdf, Stream.Size);
        if Stream.Size > 0 then
        begin
          Stream.Position := 0;
          Stream.ReadBuffer(APdf[0], Stream.Size);
        end;
      finally
        Stream.Free;
        ACBr.DANFE := nil;
        Danfe.Free;
      end;
    finally
      ACBr.Free;
    end;
    Result := Length(APdf) > 0;
    if not Result then
      AErro := 'O ACBr nao gerou o PDF da DANFE.';
  except
    on E: Exception do
      AErro := 'Erro ao gerar o PDF da DANFE: ' + E.Message;
  end;
end;

end.
