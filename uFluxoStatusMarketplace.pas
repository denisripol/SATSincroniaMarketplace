// ============================================================================
// UNIT: uFluxoStatusMarketplace
// OBJETIVO: janela do botao "Observacao Status" da tela de pedidos
// (04/11/2026) - mostra ao lojista a ordem normal dos status do pedido no
// marketplace da loja aberta e qual botao da tela usar em cada etapa.
//
// O texto segue o que a tela faz hoje (DescreverSituacaoPedido e os
// handlers dos botoes em uFrmPedidosMarketplace). Mudou um botao ou um
// status la', atualizar aqui tambem.
//
// Formato do texto: linha comecando com "# " = titulo, "## " = secao (os
// dois em negrito); o resto e' texto normal.
// ============================================================================
unit uFluxoStatusMarketplace;

interface

uses
  Vcl.Forms, uMarketplace;

procedure MostrarFluxoStatus(const AMarketplace: TMarketplaces;
  const ANomeLoja: string);

// Monta a janela sem exibir (quem chama exibe e libera).
function CriarFormFluxoStatus(const AMarketplace: TMarketplaces;
  const ANomeLoja: string): TForm;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes, Vcl.Graphics, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls;

const
  TEXTO_COMUM =
    '## Como ler'#13#10 +
    'Abaixo está a ordem normal de um pedido, do pagamento à entrega. Em cada ' +
    'etapa aparece o status que a coluna "Status" mostra, o que ele significa ' +
    'e o que fazer nesta tela.'#13#10 +
    'A coluna "Situação / próximo passo" da lista já mostra, pedido a pedido, ' +
    'o que fazer em seguida.'#13#10 +
    #13#10 +
    '## Regra geral'#13#10 +
    '1) Baixar Pedido SAT - gera a venda no SAT e baixa o estoque.'#13#10 +
    '2) Emitir a nota fiscal no SAT - a coluna "NF" passa a mostrar o número.'#13#10 +
    '3) Enviar a nota fiscal ao marketplace.'#13#10 +
    '4) Despachar e imprimir a etiqueta.'#13#10 +
    'Pedido finalizado e com a nota fiscal enviada deixa de aparecer na lista.'#13#10 +
    'Pedido cancelado depois de baixado: a venda precisa ser cancelada ' +
    'manualmente no SAT.'#13#10 +
    #13#10;

  TEXTO_SHOPEE =
    '## Fluxo normal'#13#10 +
    '1. UNPAID - Aguardando o pagamento do comprador.'#13#10 +
    '   Nada a fazer: aguardar.'#13#10 +
    #13#10 +
    '2. READY_TO_SHIP - Pago, pronto para despachar.'#13#10 +
    '   a) Baixar Pedido SAT'#13#10 +
    '   b) Emitir a nota fiscal no SAT'#13#10 +
    '   c) Enviar Nota Fiscal (envia os dados da nota e o PDF da DANFE)'#13#10 +
    '   d) Despachar'#13#10 +
    #13#10 +
    '3. PROCESSED - Envio organizado, aguardando a transportadora coletar.'#13#10 +
    '   Gerar Etiqueta, depois Baixar Etiqueta. Imprimir, colar no pacote e ' +
    'aguardar a coleta.'#13#10 +
    #13#10 +
    '4. SHIPPED - Coletado, a caminho do comprador.'#13#10 +
    '   Nada a fazer.'#13#10 +
    #13#10 +
    '5. TO_CONFIRM_RECEIVE - Entregue, aguardando o comprador confirmar.'#13#10 +
    '   Nada a fazer.'#13#10 +
    #13#10 +
    '6. COMPLETED - Concluído.'#13#10 +
    '   Nada a fazer. Sai da lista quando a nota fiscal já foi enviada.'#13#10 +
    #13#10 +
    '## Fora do fluxo normal'#13#10 +
    '- RETRY_SHIP - a coleta não aconteceu: Despachar novamente.'#13#10 +
    '- IN_CANCEL - o comprador pediu o cancelamento: Aprovar Cancelamento ou ' +
    'Reprovar Cancelamento.'#13#10 +
    '- Para cancelar um pedido ainda não concluído: Cancelar.'#13#10 +
    '- CANCELLED - Cancelado.'#13#10 +
    '- TO_RETURN - o comprador pediu devolução: tratar no Seller Centre da ' +
    'Shopee.'#13#10 +
    '- Baixar Nota Fiscal: baixa a nota que já está na Shopee, para conferir.'#13#10;

  TEXTO_AMAZON =
    '## Fluxo normal'#13#10 +
    '1. Pending / PendingAvailability - Pagamento em análise pela Amazon.'#13#10 +
    '   Nada a fazer: aguardar.'#13#10 +
    #13#10 +
    '2. Unshipped - Pago, aguardando envio.'#13#10 +
    '   a) Baixar Pedido SAT'#13#10 +
    '   b) Emitir a nota fiscal no SAT'#13#10 +
    '   c) Despachar (informar transportadora, código de rastreio e data)'#13#10 +
    '   d) Enviar Nota Fiscal (envia o XML da nota)'#13#10 +
    #13#10 +
    '3. InvoiceUnconfirmed - Enviado, com a nota fiscal ainda não confirmada ' +
    'pela Amazon.'#13#10 +
    '   Enviar Nota Fiscal.'#13#10 +
    #13#10 +
    '4. Shipped - Enviado.'#13#10 +
    '   Etapa final (a Amazon não tem status de "entregue"). Sai da lista ' +
    'quando a nota fiscal já foi enviada.'#13#10 +
    #13#10 +
    '## Fora do fluxo normal'#13#10 +
    '- PartiallyShipped - parte dos itens já foi enviada: Despachar os ' +
    'itens restantes.'#13#10 +
    '- Canceled - Cancelado.'#13#10 +
    '- Unfulfillable - a Amazon não consegue atender o pedido.'#13#10 +
    '- Etiqueta e cancelamento: pelo Seller Central da Amazon (não ' +
    'disponíveis nesta tela).'#13#10;

  TEXTO_MAGALU =
    '## Atenção'#13#10 +
    'Os nomes de status do Magalu ainda não foram conferidos com um pedido ' +
    'real.'#13#10 +
    #13#10 +
    '## Fluxo normal'#13#10 +
    '1. NEW / CREATED - Criado, aguardando a aprovação do pagamento.'#13#10 +
    '   Nada a fazer: aguardar.'#13#10 +
    #13#10 +
    '2. APPROVED - Pago, aguardando nota fiscal e envio.'#13#10 +
    '   a) Baixar Pedido SAT'#13#10 +
    '   b) Emitir a nota fiscal no SAT'#13#10 +
    '   c) Enviar a nota fiscal pelo Portal do Seller do Magalu'#13#10 +
    #13#10 +
    '3. INVOICED - Nota fiscal enviada.'#13#10 +
    '   Despachar.'#13#10 +
    #13#10 +
    '4. SHIPPED - Enviado.'#13#10 +
    '   Nada a fazer.'#13#10 +
    #13#10 +
    '5. DELIVERED - Entregue.'#13#10 +
    '   Nada a fazer. Sai da lista quando a nota fiscal do SAT já está ' +
    'autorizada.'#13#10 +
    #13#10 +
    '## Fora do fluxo normal'#13#10 +
    '- CANCELED - Cancelado.'#13#10 +
    '- Nota fiscal, etiqueta e cancelamento: pelo Portal do Seller do Magalu ' +
    '(não disponíveis nesta tela).'#13#10;

  TEXTO_MERCADOLIVRE =
    '## Como o Mercado Livre mostra o status'#13#10 +
    'A coluna "Status" mostra o status do pedido e, entre parênteses, o do ' +
    'envio. Ex.: paid (envio: handling).'#13#10 +
    #13#10 +
    '## Fluxo normal'#13#10 +
    '1. payment_required / payment_in_process - Aguardando a confirmação do ' +
    'pagamento.'#13#10 +
    '   Nada a fazer: aguardar.'#13#10 +
    #13#10 +
    '2. paid (envio: pending) - Pago, envio ainda sendo preparado pelo ' +
    'Mercado Livre.'#13#10 +
    '   Pode Baixar Pedido SAT; aguardar o Mercado Livre liberar o envio.'#13#10 +
    #13#10 +
    '3. paid (envio: handling) - Pago, aguardando o vendedor preparar o ' +
    'pacote.'#13#10 +
    '   a) Baixar Pedido SAT'#13#10 +
    '   b) Emitir a nota fiscal no SAT e enviá-la pelo portal do Mercado Livre'#13#10 +
    '   c) Baixar Etiqueta (no Mercado Livre não existe "Gerar Etiqueta")'#13#10 +
    '   d) Preparar o pacote'#13#10 +
    #13#10 +
    '4. paid (envio: ready_to_ship) - Etiqueta pronta, aguardando postagem ou ' +
    'coleta.'#13#10 +
    '   Postar o pacote ou aguardar a coleta.'#13#10 +
    #13#10 +
    '5. paid (envio: shipped) - A caminho do comprador.'#13#10 +
    '   Nada a fazer.'#13#10 +
    #13#10 +
    '6. paid (envio: delivered) - Entregue.'#13#10 +
    '   Nada a fazer. Sai da lista quando a nota fiscal do SAT já está ' +
    'autorizada.'#13#10 +
    #13#10 +
    '## Fora do fluxo normal'#13#10 +
    '- paid sem status de envio - entrega a combinar ou envio não consultado: ' +
    'conferir no portal do Mercado Livre.'#13#10 +
    '- envio not_delivered - saiu mas não foi entregue: conferir no portal.'#13#10 +
    '- cancelled / pending_cancel - Cancelado ou em cancelamento.'#13#10 +
    '- Despachar, cancelamentos e nota fiscal: pelo portal do Mercado Livre ' +
    '(não disponíveis nesta tela).'#13#10;

  TEXTO_TIKTOK =
    '## Fluxo normal'#13#10 +
    '1. UNPAID - Aguardando o pagamento do comprador.'#13#10 +
    '   Nada a fazer: aguardar.'#13#10 +
    #13#10 +
    '2. ON_HOLD - Pago, no período em que o comprador ainda pode cancelar.'#13#10 +
    '   Aguardar. Ainda não dá para baixar no SAT.'#13#10 +
    #13#10 +
    '3. AWAITING_SHIPMENT - Pago, aguardando envio.'#13#10 +
    '   a) Baixar Pedido SAT'#13#10 +
    '   b) Emitir a nota fiscal no SAT e enviá-la pelo Seller Center do TikTok'#13#10 +
    '   c) Despachar'#13#10 +
    '   d) Baixar Etiqueta (no TikTok a etiqueta só existe depois do ' +
    'Despachar)'#13#10 +
    #13#10 +
    '4. AWAITING_COLLECTION - Pacote pronto, aguardando a transportadora ' +
    'coletar.'#13#10 +
    '   Aguardar a coleta.'#13#10 +
    #13#10 +
    '5. IN_TRANSIT - A caminho do comprador.'#13#10 +
    '   Nada a fazer.'#13#10 +
    #13#10 +
    '6. DELIVERED - Entregue.'#13#10 +
    '   Nada a fazer.'#13#10 +
    #13#10 +
    '7. COMPLETED - Concluído.'#13#10 +
    '   Nada a fazer. Sai da lista quando a nota fiscal do SAT já está ' +
    'autorizada.'#13#10 +
    #13#10 +
    '## Fora do fluxo normal'#13#10 +
    '- PARTIALLY_SHIPPING - parte dos itens já foi enviada: Despachar os ' +
    'itens restantes.'#13#10 +
    '- Pedido de cancelamento do comprador: Aprovar Cancelamento ou Reprovar ' +
    'Cancelamento.'#13#10 +
    '- CANCELLED - Cancelado.'#13#10 +
    '- Cancelar pelo vendedor e nota fiscal: pelo Seller Center do TikTok ' +
    '(não disponíveis nesta tela).'#13#10;

function TextoDoMarketplace(const AMarketplace: TMarketplaces): string;
begin
  case AMarketplace of
    TMarketplaces.Shopee: Result := TEXTO_SHOPEE;
    TMarketplaces.Amazon: Result := TEXTO_AMAZON;
    TMarketplaces.Magalu: Result := TEXTO_MAGALU;
    TMarketplaces.MercadoLivre: Result := TEXTO_MERCADOLIVRE;
    TMarketplaces.TikTokShop: Result := TEXTO_TIKTOK;
  else
    Result := '## Fluxo'#13#10 +
      'Fluxo de status ainda não descrito para este marketplace.'#13#10;
  end;
end;

procedure EscreverTexto(ARich: TRichEdit; const ATexto: string);
var
  Linhas: TStringList;
  Linha: string;
  I: Integer;

  procedure Adicionar(const AConteudo: string; AEstilo: TFontStyles;
    ATamanho: Integer);
  begin
    ARich.SelStart := ARich.GetTextLen;
    ARich.SelAttributes.Style := AEstilo;
    ARich.SelAttributes.Size := ATamanho;
    ARich.SelText := AConteudo + #13#10;
  end;

begin
  Linhas := TStringList.Create;
  try
    Linhas.Text := ATexto;
    for I := 0 to Linhas.Count - 1 do
    begin
      Linha := Linhas[I];
      if Linha.StartsWith('# ') then
        Adicionar(Copy(Linha, 3, MaxInt), [fsBold], 13)
      else if Linha.StartsWith('## ') then
        Adicionar(Copy(Linha, 4, MaxInt), [fsBold], 11)
      else
        Adicionar(Linha, [], 10);
    end;
  finally
    Linhas.Free;
  end;
end;

function CriarFormFluxoStatus(const AMarketplace: TMarketplaces;
  const ANomeLoja: string): TForm;
var
  Rich: TRichEdit;
  Painel: TPanel;
  BotaoFechar: TButton;
  Titulo: string;
begin
  Titulo := 'Fluxo de status - ' + NomeMarketplace(AMarketplace);
  if ANomeLoja <> '' then
    Titulo := Titulo + ' - ' + ANomeLoja;
  Result := TForm.Create(nil);
  try
    Result.Caption := 'Observação Status';
    Result.BorderIcons := [biSystemMenu, biMaximize];
    Result.Position := poScreenCenter;
    Result.Width := 860;
    Result.Height := 640;
    Result.Font.Name := 'Segoe UI';
    Result.Font.Size := 10;

    Painel := TPanel.Create(Result);
    Painel.Parent := Result;
    Painel.Align := alBottom;
    Painel.Height := 48;
    Painel.BevelOuter := bvNone;

    BotaoFechar := TButton.Create(Result);
    BotaoFechar.Parent := Painel;
    BotaoFechar.Caption := 'Fechar';
    BotaoFechar.Width := 110;
    BotaoFechar.Height := 32;
    BotaoFechar.Top := 8;
    BotaoFechar.Left := Painel.ClientWidth - BotaoFechar.Width - 12;
    BotaoFechar.Anchors := [akTop, akRight];
    BotaoFechar.ModalResult := mrOk;
    BotaoFechar.Cancel := True;  // Esc fecha
    BotaoFechar.Default := True;

    Rich := TRichEdit.Create(Result);
    Rich.Parent := Result;
    Rich.Align := alClient;
    Rich.ReadOnly := True;
    Rich.ScrollBars := ssVertical;
    Rich.WordWrap := True;
    Rich.BorderStyle := bsNone;
    Rich.Font.Name := 'Segoe UI';
    Rich.Font.Size := 10;
    Rich.Lines.Clear;
    EscreverTexto(Rich, '# ' + Titulo + #13#10#13#10 + TEXTO_COMUM +
      TextoDoMarketplace(AMarketplace));
    Rich.SelStart := 0;
  except
    Result.Free;
    raise;
  end;
end;

procedure MostrarFluxoStatus(const AMarketplace: TMarketplaces;
  const ANomeLoja: string);
var
  Form: TForm;
begin
  Form := CriarFormFluxoStatus(AMarketplace, ANomeLoja);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

end.
