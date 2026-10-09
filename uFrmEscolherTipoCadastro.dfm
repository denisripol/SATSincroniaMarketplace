object FrmEscolherTipoCadastro: TFrmEscolherTipoCadastro
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Como voc'#234' quer cadastrar o produto?'
  ClientHeight = 260
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 15
  object lblTitulo: TLabel
    Left = 12
    Top = 12
    Width = 436
    Height = 15
    Caption = 'Escolha como cadastrar o produto neste marketplace:'
  end
  object pnlCards: TScrollBox
    Left = 12
    Top = 36
    Width = 436
    Height = 168
    VertScrollBar.Tracking = True
    TabOrder = 0
  end
  object CmdCancelar: TBitBtn
    Left = 348
    Top = 212
    Width = 100
    Height = 34
    Caption = 'Cancelar'
    TabOrder = 1
    OnClick = CmdCancelarClick
  end
end
