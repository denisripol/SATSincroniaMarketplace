program SATSincroniaMarketplace;

uses
  Forms,
  SysUtils,
  Controls,
  Windows,
  Messages,
  uFrmSincroniaMarketplace in 'uFrmSincroniaMarketplace.pas' {FrmSincroniaMarketplace},
  uFrmPedidosMarketplace in 'uFrmPedidosMarketplace.pas' {FrmPedidosMarketplace},
  uFrmOfertasMarketplace in 'uFrmOfertasMarketplace.pas' {FrmOfertasMarketplace},
  uFrmVincularProduto in 'uFrmVincularProduto.pas' {FrmVincularProduto},
  uFrmCadastrarProdutoMarketplace in 'uFrmCadastrarProdutoMarketplace.pas' {FrmCadastrarProdutoMarketplace},
  uFrmConfigSincroniaAutomatica in 'uFrmConfigSincroniaAutomatica.pas' {FrmConfigSincroniaAutomatica},
  DMZ in '..\Comum\DMZ.pas' {DZ: TDataModule},
  SATConstantes in '..\SatUtil\SATConstantes.pas',
  SATVariaveis in '..\SatUtil\SATVariaveis.pas',
  SATFuncoesBD in '..\SatUtil\SATFuncoesBD.pas',
  ConfiguracaoLocal in '..\Comum\ConfiguracaoLocal.pas' {ConfigLocal: TDataModule},
  Funcoes in '..\Comum\Funcoes.pas',
  uMarketplace in '..\Comum\uMarketplace.pas',
  Shopee.OpenAPI.Client in '..\Comum\Shopee.OpenAPI.Client.pas',
  Amazon.SPAPI.Client in '..\Comum\Amazon.SPAPI.Client.pas',
  Magalu.OpenAPI.Client in '..\Comum\Magalu.OpenAPI.Client.pas',
  DM in '..\Comum\DM.pas' {d: TDataModule},
  SATFuncoes in '..\SATUtil\SATFuncoes.pas',
  DlgInformacao in '..\Comum\DlgInformacao.pas' {FrmDlgInformacao},
  SATFuncoesComFormularios in '..\SATUtil\SATFuncoesComFormularios.pas',
  DWait in '..\SATUtil\DWait.pas' {DlgWait},
  uLayout in '..\Comum\uLayout.pas',
  DDate in '..\SATUtil\DDate.pas' {DlgDate},
  Navigator in '..\SATUtil\Navigator.pas' {SATNav: TFrame},
  Licenca in '..\Comum\Licenca.pas' {SATLicenca: TDataModule},
  SATProcessosFilhoComum in '..\Comum\SATProcessosFilhoComum.pas',
  SAT.Types in '..\Comum\SAT.Types.pas',
  Dlg in '..\SATUtil\Dlg.pas' {FrmDlg},
  uLayoutPDV in '..\Comum\uLayoutPDV.pas',
  uFrmCadastrarProdutoAmazonNovo in 'uFrmCadastrarProdutoAmazonNovo.pas' {FrmCadastrarProdutoAmazonNovo},
  uRoteadorIncluirProduto in 'uRoteadorIncluirProduto.pas',
  uFrmEscolherTipoCadastro in 'uFrmEscolherTipoCadastro.pas' {FrmEscolherTipoCadastro},
  uModosCadastroProduto in 'uModosCadastroProduto.pas',
  uFrmDespacharAmazon in 'uFrmDespacharAmazon.pas' {FrmDespacharAmazon},
  MercadoLivre.OpenAPI.Client in '..\Comum\MercadoLivre.OpenAPI.Client.pas',
  TikTokShop.OpenAPI.Client in '..\Comum\TikTokShop.OpenAPI.Client.pas',
  uFrmCadastrarProdutoMercadoLivreNovo in 'uFrmCadastrarProdutoMercadoLivreNovo.pas' {FrmCadastrarProdutoMercadoLivreNovo},
  uFrmCadastrarOfertaCatalogoMercadoLivre in 'uFrmCadastrarOfertaCatalogoMercadoLivre.pas' {FrmCadastrarOfertaCatalogoMercadoLivre},
  uFrmCadastrarProdutoTikTokNovo in 'uFrmCadastrarProdutoTikTokNovo.pas' {FrmCadastrarProdutoTikTokNovo};

// {NOTA} Lista atualizada com as dependencias transitivas que foram
// aparecendo na primeira compilada (DM, SATFuncoes, DlgInformacao,
// SATFuncoesComFormularios, DWait, uLayout, DDate, Navigator, Licenca,
// SATProcessosFilhoComum, SAT.Types, Dlg, uLayoutPDV) - ainda bem mais
// enxuta que o SATSincronia original (sem DNF, DBDSAT, DCertificado, DMBal,
// ImpressaoSpooler, SATProcessoPai, InstancesController).

{$R *.res}

var
  hPrevInst: THandle;

begin
  try
    {$IFDEF DEBUG}
    ReportMemoryLeaksOnShutdown := True;
    {$ENDIF}

    FormatSettings.ShortDateFormat := 'dd/MM/yy';
    FormatSettings.ShortTimeFormat := 'hh:mm';
    FormatSettings.DateSeparator := '/';
    FormatSettings.LongTimeFormat := 'hh:mm:ss';
    FormatSettings.CurrencyString := 'R$';
    FormatSettings.CurrencyFormat := 2;
    FormatSettings.NegCurrFormat := 12;

    Screen.Cursor := crHourglass;
    Application.Title := 'SAT - Sincronia Marketplace';
    VG.Versao := '260810A';

    // Mesmo padrao de instancia unica do SATSincronia original - se ja tiver
    // uma copia rodando (minimizada na bandeja), so restaura ela em vez de
    // abrir uma segunda.
    if VerificarSeAplicativoEstaEmExecucao(cvNomeCompletoDoArquivo) then
    begin
      hPrevInst := FindWindow('TFrmSincroniaMarketplace', nil);
      if hPrevInst <> 0 then
        SendMessage(hPrevInst, WM_SHOWSINCRONIA, 0, 0);
      Application.Terminate;
    end
    else
    begin
      Application.Initialize;

      Application.CreateForm(TDZ, DZ);
  try
        try
          ConfigLocal.ReadIniFile('');
          ConectarBD;

          Application.CreateForm(TFrmSincroniaMarketplace, FrmSincroniaMarketplace);
          Application.MainFormOnTaskbar := False;

          if ParamStr(1) = '-e' then
            FrmSincroniaMarketplace.Restaurar
          else
          begin
            FrmSincroniaMarketplace.Hide;
            FrmSincroniaMarketplace.EsconderJanela;
          end;

          Screen.Cursor := crDefault;
        except
          on E: Exception do
            Application.ShowException(E);
        end;
      finally
        // {TODO} confirmar se e' desejavel desconectar aqui como no
        // SATSincronia original - se o timer/tela precisar da conexao viva
        // apos o startup, remover esta linha.
        // DZ.ZDatabase.Connected := False;
      end;

      Application.Run;
    end;
  except
    on E: Exception do
    begin
      E.Message := 'Erro ao iniciar o SAT Sincronia Marketplace.' + #13#13 + E.Message;
      Application.ShowException(E);
      Exit;
    end;
  end;
end.
